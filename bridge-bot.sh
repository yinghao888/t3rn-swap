#!/bin/bash

# === 颜色定义 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# === 脚本路径和配置 ===
ARB_SCRIPT="uni-arb.py"
OP_SCRIPT="op-uni.py"
BALANCE_SCRIPT="balance-notifier.py"
BOT_TOKEN="8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38"
CONFIG_FILE="accounts.json"
DIRECTION_FILE="direction.conf"
TELEGRAM_CONFIG="telegram.conf"
PYTHON_VERSION="3.8"
PM2_PROCESS_NAME="bridge-bot"
PM2_BALANCE_NAME="balance-notifier"

# === 横幅 ===
banner() {
    clear
    echo -e "${CYAN}"
    echo "=================================================="
    echo "          跨链桥自动化脚本 by @hao3313076         "
    echo "=================================================="
    echo "关注 Twitter: JJ长10cm | 高效跨链，安全可靠！"
    echo "=================================================="
    echo -e "${NC}"
}

# === 检查 root 权限 ===
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：请以 root 权限运行此脚本（使用 sudo）！${NC}"
        exit 1
    fi
}

# === 安装依赖 ===
install_dependencies() {
    echo -e "${CYAN}正在检查和安装必要的依赖...${NC}"
    apt-get update -y || { echo -e "${RED}无法更新包列表${NC}"; exit 1; }
    for pkg in curl wget python3 python3-pip python3-dev; do
        if ! dpkg -l | grep -q "^ii.*$pkg "; then
            echo -e "${CYAN}安装 $pkg...${NC}"
            apt-get install -y "$pkg" || { echo -e "${RED}无法安装 $pkg${NC}"; exit 1; }
        else
            echo -e "${GREEN}$pkg 已安装${NC}"
        fi
    done
    if ! command -v python${PYTHON_VERSION} >/dev/null 2>&1; then
        echo -e "${CYAN}安装 Python ${PYTHON_VERSION}...${NC}"
        apt-get install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-dev || echo -e "${RED}使用默认 Python${NC}"
    fi
    if ! command -v pm2 >/dev/null 2>&1; then
        echo -e "${CYAN}安装 Node.js 和 PM2...${NC}"
        curl -sL https://deb.nodesource.com/setup_16.x | bash -
        apt-get install -y nodejs && npm install -g pm2 || { echo -e "${RED}无法安装 PM2${NC}"; exit 1; }
    fi
    for py_pkg in web3 python-telegram-bot; do
        if ! python3 -m pip show "$py_pkg" >/dev/null 2>&1; then
            echo -e "${CYAN}安装 $py_pkg...${NC}"
            pip3 install "$py_pkg" || { echo -e "${RED}无法安装 $py_pkg${NC}"; exit 1; }
        fi
    done
    echo -e "${GREEN}依赖安装完成！${NC}"
}

# === 下载 Python 脚本 ===
download_python_scripts() {
    echo -e "${CYAN}下载 Python 脚本...${NC}"
    for script in "$ARB_SCRIPT" "$OP_SCRIPT" "$BALANCE_SCRIPT"; do
        wget -O "$script" "https://raw.githubusercontent.com/yinghao888/t3rn-swap/main/$script" || { echo -e "${RED}无法下载 $script${NC}"; exit 1; }
        chmod +x "$script"
        echo -e "${GREEN}$script 下载完成${NC}"
    done
}

# === 初始化配置文件 ===
init_config() {
    [ ! -f "$CONFIG_FILE" ] && echo '[]' > "$CONFIG_FILE" && echo -e "${GREEN}创建 $CONFIG_FILE${NC}"
    [ ! -f "$DIRECTION_FILE" ] && echo "arb_to_uni" > "$DIRECTION_FILE" && echo -e "${GREEN}默认方向: ARB -> UNI${NC}"
}

# === 读取账户 ===
read_accounts() {
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo '[]'
    else
        cat "$CONFIG_FILE"
    fi
}

# === 添加私钥 ===
add_private_key() {
    echo -e "${CYAN}请输入私钥（带或不带 0x，多个用 + 分隔，例如 key1+key2）：${NC}"
    read -p "> " private_keys
    IFS='+' read -ra keys <<< "$private_keys"
    accounts=$(read_accounts)
    if [ "$accounts" == "[]" ]; then
        new_accounts="[]"
    else
        new_accounts="$accounts"
    fi
    count=$(grep -o '"name":' "$CONFIG_FILE" | wc -l)
    for key in "${keys[@]}"; do
        key=$(echo "$key" | tr -d '[:space:]')
        key=${key#0x}
        if [[ ! "$key" =~ ^[0-9a-fA-F]{64}$ ]]; then
            echo -e "${RED}无效私钥：${key:0:10}...（需 64 位十六进制）${NC}"
            continue
        fi
        formatted_key="0x$key"
        count=$((count + 1))
        name="Account$count"
        new_entry="{\"name\": \"$name\", \"private_key\": \"$formatted_key\"}"
        if [ "$new_accounts" == "[]" ]; then
            new_accounts="[$new_entry]"
        else
            new_accounts=$(echo "$new_accounts" | sed "s/]$/, $new_entry]/")
        fi
    done
    echo "$new_accounts" > "$CONFIG_FILE"
    update_python_accounts
    echo -e "${GREEN}已添加 ${#keys[@]} 个账户${NC}"
}

# === 删除私钥 ===
delete_private_key() {
    accounts=$(read_accounts)
    count=$(echo "$accounts" | grep -o '"name":' | wc -l)
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}账户列表为空！${NC}"
        return
    fi
    echo -e "${CYAN}当前账户列表：${NC}"
    i=1
    while IFS= read -r line; do
        name=$(echo "$line" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
        key=$(echo "$line" | grep -o '"private_key": "[^"]*"' | cut -d'"' -f4)
        [ -n "$name" ] && echo "$i. $name (${key:0:10}...)"
        i=$((i + 1))
    done <<< "$(echo "$accounts" | tr '[]' '\n' | tr ',' '\n')"
    echo -e "${CYAN}请输入要删除的账户编号（或 0 取消）：${NC}"
    read -p "> " index
    [ "$index" -eq 0 ] && return
    if [ -z "$index" ] || [ "$index" -le 0 ] || [ "$index" -gt "$count" ]; then
        echo -e "${RED}无效编号！${NC}"
        return
    fi
    new_accounts=$(echo "$accounts" | awk -v idx="$index" 'BEGIN{RS="},{";ORS="},{"}NR!=idx{print $0}' | sed 's/},{/}, {/g')
    new_accounts="[${new_accounts}]"
    echo "$new_accounts" > "$CONFIG_FILE"
    update_python_accounts
    echo -e "${GREEN}已删除账户！${NC}"
}

# === 更新 Python 脚本账户 ===
update_python_accounts() {
    accounts=$(read_accounts)
    accounts_str=$(echo "$accounts" | sed 's/"/\\"/g')
    sed -i "s|ACCOUNTS = \[.*\]|ACCOUNTS = $accounts_str|" "$ARB_SCRIPT"
    sed -i "s|ACCOUNTS = \[.*\]|ACCOUNTS = $accounts_str|" "$OP_SCRIPT"
    echo -e "${GREEN}已更新 $ARB_SCRIPT 和 $OP_SCRIPT${NC}"
}

# === 选择跨链方向 ===
select_direction() {
    echo -e "${CYAN}请选择跨链方向：${NC}"
    echo "1. ARB -> UNI"
    echo "2. OP <-> UNI (双向)"
    read -p "> " choice
    case $choice in
        1) echo "arb_to_uni" > "$DIRECTION_FILE"; echo -e "${GREEN}设置为 ARB -> UNI${NC}" ;;
        2) echo "both" > "$DIRECTION_FILE"; echo -e "${GREEN}设置为 OP <-> UNI${NC}" ;;
        *) echo -e "${RED}无效选项，默认 ARB -> UNI${NC}"; echo "arb_to_uni" > "$DIRECTION_FILE" ;;
    esac
}

# === 配置 Telegram ===
configure_telegram() {
    echo -e "${CYAN}请输入 Telegram 用户 ID：${NC}"
    read -p "> " chat_id
    [[ ! "$chat_id" =~ ^[0-9]+$ ]] && { echo -e "${RED}无效 ID！${NC}"; return; }
    echo "chat_id=$chat_id" > "$TELEGRAM_CONFIG"
    echo -e "${GREEN}Telegram 配置完成！${NC}"
}

# === 删除脚本 ===
delete_script() {
    echo -e "${RED}警告：将删除所有脚本和配置！继续？(y/n)${NC}"
    read -p "> " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
        pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
        rm -f "$ARB_SCRIPT" "$OP_SCRIPT" "$BALANCE_SCRIPT" "$CONFIG_FILE" "$DIRECTION_FILE" "$TELEGRAM_CONFIG" "$0"
        echo -e "${GREEN}已删除所有文件！${NC}"
        exit 0
    fi
}

# === 启动跨链脚本 ===
start_bridge() {
    accounts=$(read_accounts)
    [ "$(echo "$accounts" | grep -o '"name":' | wc -l)" -eq 0 ] && { echo -e "${RED}请先添加账户！${NC}"; return; }
    direction=$(cat "$DIRECTION_FILE")
    pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    [ "$direction" = "arb_to_uni" ] && pm2 start "$ARB_SCRIPT" --name "$PM2_PROCESS_NAME" --interpreter python3 || pm2 start "$OP_SCRIPT" --name "$PM2_PROCESS_NAME" --interpreter python3
    pm2 start "$BALANCE_SCRIPT" --name "$PM2_BALANCE_NAME" --interpreter python3
    pm2 save
    echo -e "${GREEN}脚本已启动！使用 'pm2 logs' 查看日志${NC}"
}

# === 主菜单 ===
main_menu() {
    while true; do
        banner
        echo -e "${CYAN}请选择操作：${NC}"
        echo "1. 管理私钥  2. 选择跨链方向  3. 配置 Telegram"
        echo "4. 删除脚本  5. 启动跨链脚本  6. 退出"
        read -p "> " choice
        case $choice in
            1)
                while true; do
                    banner
                    echo -e "${CYAN}私钥管理：${NC}"
                    echo "1. 添加私钥  2. 删除私钥  3. 返回"
                    read -p "> " sub_choice
                    case $sub_choice in
                        1) add_private_key ;;
                        2) delete_private_key ;;
                        3) break ;;
                        *) echo -e "${RED}无效选项！${NC}" ;;
                    esac
                    read -p "按回车继续..."
                done
                ;;
            2) select_direction ;;
            3) configure_telegram ;;
            4) delete_script ;;
            5) start_bridge ;;
            6) echo -e "${GREEN}退出！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项！${NC}" ;;
        esac
        read -p "按回车继续..."
    done
}

# === 主程序 ===
check_root
install_dependencies
download_python_scripts
init_config
main_menu
