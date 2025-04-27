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
    for pkg in curl wget jq python3 python3-pip python3-dev; do
        if ! dpkg -l | grep -q "^ii.*$pkg "; then
            echo -e "${CYAN}安装 $pkg...${NC}"
            apt-get install -y "$pkg" || { echo -e "${RED}无法安装 $pkg${NC}"; exit 1; }
        else
            echo -e "${GREEN}$pkg 已安装${NC}"
        fi
    done
    if ! command -v python${PYTHON_VERSION} >/dev/null 2>&1; then
        echo -e "${CYAN}安装 Python ${PYTHON_VERSION}...${NC}"
        apt-get install -y software-properties-common && add-apt-repository ppa:deadsnakes/ppa -y && apt-get update -y
        apt-get install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-distutils || {
            echo -e "${RED}无法安装 Python ${PYTHON_VERSION}，使用默认 Python${NC}"
            command -v python3 >/dev/null 2>&1 || { echo -e "${RED}无可用 Python${NC}"; exit 1; }
        }
        curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
        python${PYTHON_VERSION} get-pip.py && rm get-pip.py
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
    if ! python3 -m pip show python-telegram-bot | grep -q "Version:.*\[all\]"; then
        echo -e "${CYAN}安装 python-telegram-bot[all]...${NC}"
        pip3 install python-telegram-bot[all] || { echo -e "${RED}无法安装 python-telegram-bot[all]${NC}"; exit 1; }
    fi
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
        return
    fi
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}警告：$CONFIG_FILE 格式无效，重置为空列表${NC}"
        echo '[]' > "$CONFIG_FILE"
        echo '[]'
        return
    fi
    cat "$CONFIG_FILE"
}

# === 添加私钥 ===
add_private_key() {
    echo -e "${CYAN}请输入私钥（带或不带 0x，多个用 + 分隔，例如 key1+key2）：${NC}"
    read -p "> " private_keys
    IFS='+' read -ra keys <<< "$private_keys"
    accounts=$(read_accounts)
    temp_file=$(mktemp)
    echo "$accounts" > "$temp_file"
    count=$(echo "$accounts" | jq 'length')
    added=0
    new_accounts=()
    for key in "${keys[@]}"; do
        key=$(echo "$key" | tr -d '[:space:]')
        key=${key#0x}
        if [[ ! "$key" =~ ^[0-9a-fA-F]{64}$ ]]; then
            echo -e "${RED}无效私钥：${key:0:10}...（需 64 位十六进制）${NC}"
            continue
        fi
        formatted_key="0x$key"
        if echo "$accounts" | jq -e ".[] | select(.private_key == \"$formatted_key\")" >/dev/null 2>&1; then
            echo -e "${RED}私钥 ${formatted_key:0:10}... 已存在，跳过${NC}"
            continue
        fi
        count=$((count + 1))
        name="Account$count"
        new_entry="{\"name\": \"$name\", \"private_key\": \"$formatted_key\"}"
        new_accounts+=("$new_entry")
        added=$((added + 1))
    done
    if [ $added -eq 0 ]; then
        rm "$temp_file"
        echo -e "${RED}未添加任何新私钥${NC}"
        return
    fi
    accounts_json=$(echo "$accounts" | jq -c '.')
    for entry in "${new_accounts[@]}"; do
        accounts_json=$(echo "$accounts_json $entry" | jq -s '.[0] + [.[1]]' | jq -c '.')
    done
    echo "$accounts_json" > "$CONFIG_FILE"
    rm "$temp_file"
    update_python_accounts
    echo -e "${GREEN}已添加 $added 个账户${NC}"
    echo -e "${CYAN}当前 accounts.json 内容：${NC}"
    cat "$CONFIG_FILE"
}

# === 删除私钥 ===
delete_private_key() {
    accounts=$(read_accounts)
    count=$(echo "$accounts" | jq 'length')
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}账户列表为空！${NC}"
        return
    fi
    echo -e "${CYAN}当前账户列表：${NC}"
    accounts_list=()
    i=1
    while IFS= read -r line; do
        name=$(echo "$line" | jq -r '.name')
        key=$(echo "$line" | jq -r '.private_key')
        if [ -n "$name" ] && [ -n "$key" ]; then
            accounts_list+=("$line")
            echo "$i. $name (${key:0:10}...)"
            i=$((i + 1))
        fi
    done < <(echo "$accounts" | jq -c '.[]')
    if [ ${#accounts_list[@]} -eq 0 ]; then
        echo -e "${RED}账户列表为空！${NC}"
        return
    fi
    echo -e "${CYAN}请输入要删除的账户编号（或 0 取消）：${NC}"
    read -p "> " index
    [ "$index" -eq 0 ] && return
    if [ -z "$index" ] || [ "$index" -le 0 ] || [ "$index" -gt "${#accounts_list[@]}" ]; then
        echo -e "${RED}无效编号！${NC}"
        return
    fi
    new_accounts=$(echo "$accounts" | jq -c "del(.[$((index-1))])")
    echo "$new_accounts" > "$CONFIG_FILE"
    update_python_accounts
    echo -e "${GREEN}已删除账户！${NC}"
    echo -e "${CYAN}当前 accounts.json 内容：${NC}"
    cat "$CONFIG_FILE"
}

# === 更新 Python 脚本账户 ===
update_python_accounts() {
    accounts=$(read_accounts)
    # 生成 Python 列表格式
    accounts_str=$(echo "$accounts" | jq -r '[.[] | {"private_key": .private_key, "name": .name}]' | sed 's/"/\\"/g')
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
    if [ "$accounts" == "[]" ]; then
        echo -e "${RED}请先添加账户！${NC}"
        return
    fi
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
        echo "1. 管理私钥"
        echo "2. 选择跨链方向"
        echo "3. 配置 Telegram"
        echo "4. 删除脚本"
        echo "5. 启动跨链脚本"
        echo "6. 退出"
        read -p "> " choice
        case $choice in
            1)
                while true; do
                    banner
                    echo -e "${CYAN}私钥管理：${NC}"
                    echo "1. 添加私钥"
                    echo "2. 删除私钥"
                    echo "3. 返回"
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
