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
    
    # 更新包列表
    if ! apt-get update -y; then
        echo -e "${RED}无法更新包列表，请检查网络或软件源${NC}"
        exit 1
    fi

    # 检查并安装基本工具
    for pkg in curl wget jq python3 python3-pip python3-dev; do
        if ! dpkg -l | grep -q "^ii.*$pkg "; then
            echo -e "${CYAN}安装 $pkg...${NC}"
            if ! apt-get install -y "$pkg"; then
                echo -e "${RED}无法安装 $pkg，请检查软件源${NC}"
                exit 1
            fi
        else
            echo -e "${GREEN}$pkg 已安装，跳过${NC}"
        fi
    done

    # 检查 Python 版本
    if command -v python${PYTHON_VERSION} >/dev/null 2>&1; then
        echo -e "${GREEN}Python ${PYTHON_VERSION} 已安装，跳过${NC}"
    else
        echo -e "${CYAN}未找到 Python ${PYTHON_VERSION}，尝试安装...${NC}"
        if ! apt-get install -y software-properties-common; then
            echo -e "${RED}无法安装 software-properties-common${NC}"
            exit 1
        fi
        add-apt-repository ppa:deadsnakes/ppa -y
        apt-get update -y
        if ! apt-get install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-distutils; then
            echo -e "${RED}无法安装 Python ${PYTHON_VERSION}，尝试使用系统默认 Python${NC}"
            if ! command -v python3 >/dev/null 2>&1; then
                echo -e "${RED}系统无可用 Python 版本，请手动安装${NC}"
                exit 1
            fi
        else
            echo -e "${CYAN}安装 pip for Python ${PYTHON_VERSION}...${NC}"
            curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
            python${PYTHON_VERSION} get-pip.py
            rm get-pip.py
        fi
    fi

    # 检查并安装 Node.js 和 PM2
    if command -v pm2 >/dev/null 2>&1; then
        echo -e "${GREEN}PM2 已安装，跳过${NC}"
    else
        echo -e "${CYAN}安装 Node.js 和 PM2...${NC}"
        curl -sL https://deb.nodesource.com/setup_16.x | bash -
        if ! apt-get install -y nodejs; then
            echo -e "${RED}无法安装 Node.js${NC}"
            exit 1
        fi
        npm install -g pm2
    fi

    # 检查并安装 Python 依赖
    for py_pkg in web3 python-telegram-bot; do
        if python3 -m pip show "$py_pkg" >/dev/null 2>&1; then
            echo -e "${GREEN}Python 依赖 $py_pkg 已安装，跳过${NC}"
        else
            echo -e "${CYAN}安装 Python 依赖 $py_pkg...${NC}"
            if ! pip3 install "$py_pkg"; then
                echo -e "${RED}无法安装 Python 依赖 $py_pkg${NC}"
                exit 1
            fi
        fi
    done
    if ! pip3 show python-telegram-bot | grep -q "Version:.*\[all\]"; then
        echo -e "${CYAN}安装 python-telegram-bot[all]...${NC}"
        if ! pip3 install python-telegram-bot[all]; then
            echo -e "${RED}无法安装 python-telegram-bot[all]${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}python-telegram-bot[all] 已安装，跳过${NC}"
    fi

    echo -e "${GREEN}所有依赖检查和安装完成！${NC}"
}

# === 下载 Python 脚本 ===
download_python_scripts() {
    echo -e "${CYAN}下载 Python 脚本...${NC}"
    for script in "$ARB_SCRIPT" "$OP_SCRIPT" "$BALANCE_SCRIPT"; do
        url="https://raw.githubusercontent.com/yinghao888/t3rn-swap/main/$script"
        if ! wget -O "$script" "$url"; then
            echo -e "${RED}无法下载 $script${NC}"
            exit 1
        fi
        chmod +x "$script"
        echo -e "${GREEN}$script 下载完成${NC}"
    done
}

# === 初始化配置文件 ===
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo '[]' > "$CONFIG_FILE"
        echo -e "${GREEN}已创建空的账户配置文件: $CONFIG_FILE${NC}"
    fi
    if [ ! -f "$DIRECTION_FILE" ]; then
        echo "arb_to_uni" > "$DIRECTION_FILE"
        echo -e "${GREEN}默认跨链方向: ARB -> UNI${NC}"
    fi
}

# === 读取私钥 ===
read_accounts() {
    jq -r '.' "$CONFIG_FILE" 2>/dev/null || echo '[]'
}

# === 添加私钥 ===
add_private_key() {
    echo -e "${CYAN}请输入私钥（带或不带 0x，多个私钥用 + 分隔，例如 key1+key2）：${NC}"
    read -p "> " private_keys
    # 按 + 分割私钥
    IFS='+' read -ra keys <<< "$private_keys"
    accounts=$(read_accounts)
    account_count=$(echo "$accounts" | jq length)
    new_accounts=()
    for key in "${keys[@]}"; do
        # 清理空白字符
        key=$(echo "$key" | tr -d '[:space:]')
        # 移除 0x 前缀（如果有）
        key=${key#0x}
        # 验证私钥格式（64 位十六进制）
        if [[ ! "$key" =~ ^[0-9a-fA-F]{64}$ ]]; then
            echo -e "${RED}错误：无效的私钥格式（$key），需为 64 位十六进制${NC}"
            continue
        fi
        # 添加 0x 前缀保存
        formatted_key="0x$key"
        # 生成默认账户名称
        account_count=$((account_count + 1))
        name="Account$account_count"
        # 创建新账户 JSON 对象
        new_acc=$(jq -n --arg name "$name" --arg key "$formatted_key" '{"name": $name, "private_key": $key}')
        new_accounts+=("$new_acc")
    done
    if [ ${#new_accounts[@]} -eq 0 ]; then
        echo -e "${RED}未添加任何有效私钥${NC}"
        return
    fi
    # 合并新账户到现有账户列表
    temp_file=$(mktemp)
    echo "$accounts" > "$temp_file"
    for new_acc in "${new_accounts[@]}"; do
        echo "$new_acc" | jq -s '.' > "$temp_file.new"
        mv "$temp_file.new" "$temp_file"
        accounts=$(jq -s '.[0] + .[1] | unique_by(.private_key)' "$temp_file" <(echo "$new_acc"))
        echo "$accounts" > "$temp_file"
    done
    mv "$temp_file" "$CONFIG_FILE"
    rm -f "$temp_file"*
    update_python_accounts
    echo -e "${GREEN}已添加 ${#new_accounts[@]} 个账户${NC}"
}

# === 删除私钥 ===
delete_private_key() {
    accounts=$(read_accounts)
    if [ "$(echo "$accounts" | jq length)" -eq 0 ]; then
        echo -e "${RED}错误：账户列表为空！${NC}"
        return
    fi
    echo -e "${CYAN}当前账户列表：${NC}"
    echo "$accounts" | jq -r '.[] | "\(.name) (\(.private_key | .[0:10])...)"' | nl -w2 -s '. '
    echo -e "${CYAN}请输入要删除的账户编号（或 0 取消）：${NC}"
    read -p "> " index
    if [ "$index" -eq 0 ]; then
        return
    fi
    if [ "$index" -le 0 ] || [ "$index" -gt "$(echo "$accounts" | jq length)" ]; then
        echo -e "${RED}错误：无效的编号！${NC}"
        return
    fi
    updated_accounts=$(echo "$accounts" | jq "del(.[$((index-1))])")
    echo "$updated_accounts" > "$CONFIG_FILE"
    update_python_accounts
    echo -e "${GREEN}已删除选定账户！${NC}"
}

# === 修改 Python 脚本中的账户 ===
update_python_accounts() {
    accounts=$(read_accounts)
    accounts_str=$(echo "$accounts" | jq -r '.[] | "{\"private_key\": \"\(.private_key)\", \"name\": \"\(.name)\"}"' | jq -s .)
    sed -i "s|ACCOUNTS = \[.*\]|ACCOUNTS = $accounts_str|" "$ARB_SCRIPT"
    sed -i "s|ACCOUNTS = \[.*\]|ACCOUNTS = $accounts_str|" "$OP_SCRIPT"
    echo -e "${GREEN}已更新 $ARB_SCRIPT 和 $OP_SCRIPT 中的账户列表！${NC}"
}

# === 选择跨链方向 ===
select_direction() {
    echo -e "${CYAN}请选择跨链方向：${NC}"
    echo "1. ARB -> UNI"
    echo "2. OP <-> UNI (双向)"
    echo -e "${CYAN}请输入选项（1-2）：${NC}"
    read -p "> " choice
    case $choice in
        1)
            echo "arb_to_uni" > "$DIRECTION_FILE"
            echo -e "${GREEN}已设置为 ARB -> UNI 方向！${NC}"
            ;;
        2)
            echo "both" > "$DIRECTION_FILE"
            echo -e "${GREEN}已设置为 OP <-> UNI 双向跨链！${NC}"
            ;;
        *)
            echo -e "${RED}无效选项，默认 ARB -> UNI！${NC}"
            echo "arb_to_uni" > "$DIRECTION_FILE"
            ;;
    esac
}

# === 配置 Telegram 通知 ===
configure_telegram() {
    echo -e "${CYAN}请输入 Telegram 用户 ID：${NC}"
    read -p "> " chat_id
    if [[ ! "$chat_id" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误：无效的 Telegram 用户 ID！${NC}"
        return
    fi
    echo "chat_id=$chat_id" > "$TELEGRAM_CONFIG"
    echo -e "${GREEN}Telegram 通知已配置！${NC}"
}

# === 删除脚本 ===
delete_script() {
    echo -e "${RED}警告：此操作将删除所有脚本和配置文件！${NC}"
    echo -e "${CYAN}是否继续？(y/n)${NC}"
    read -p "> " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        pm2 stop "$PM2_PROCESS_NAME" >/dev/null 2>&1
        pm2 delete "$PM2_PROCESS_NAME" >/dev/null 2>&1
        pm2 stop "$PM2_BALANCE_NAME" >/dev/null 2>&1
        pm2 delete "$PM2_BALANCE_NAME" >/dev/null 2>&1
        rm -f "$ARB_SCRIPT" "$OP_SCRIPT" "$BALANCE_SCRIPT" "$CONFIG_FILE" "$DIRECTION_FILE" "$TELEGRAM_CONFIG" "$0"
        echo -e "${GREEN}所有脚本和配置文件已删除！${NC}"
        exit 0
    else
        echo -e "${CYAN}操作已取消！${NC}"
    fi
}

# === 使用 PM2 启动跨链脚本和余额查询脚本 ===
start_bridge() {
    accounts=$(read_accounts)
    if [ "$(echo "$accounts" | jq length)" -eq 0 ]; then
        echo -e "${RED}错误：请先添加至少一个账户！${NC}"
        return
    fi
    direction=$(cat "$DIRECTION_FILE")
    echo -e "${CYAN}正在使用 PM2 启动跨链脚本和余额查询脚本...${NC}"
    pm2 stop "$PM2_PROCESS_NAME" >/dev/null 2>&1
    pm2 delete "$PM2_PROCESS_NAME" >/dev/null 2>&1
    pm2 stop "$PM2_BALANCE_NAME" >/dev/null 2>&1
    pm2 delete "$PM2_BALANCE_NAME" >/dev/null 2>&1
    if [ "$direction" = "arb_to_uni" ]; then
        pm2 start "$ARB_SCRIPT" --name "$PM2_PROCESS_NAME" --interpreter python3
    else
        pm2 start "$OP_SCRIPT" --name "$PM2_PROCESS_NAME" --interpreter python3
    fi
    pm2 start "$BALANCE_SCRIPT" --name "$PM2_BALANCE_NAME" --interpreter python3
    pm2 save
    echo -e "${GREEN}跨链脚本和余额查询脚本已通过 PM2 启动！使用 'pm2 logs $PM2_PROCESS_NAME' 查看跨链日志，或 'pm2 logs $PM2_BALANCE_NAME' 查看余额日志，或 'pm2 stop $PM2_PROCESS_NAME' 和 'pm2 stop $PM2_BALANCE_NAME' 停止。${NC}"
}

# === 主菜单 ===
main_menu() {
    while true; do
        banner
        echo -e "${CYAN}请选择操作：${NC}"
        echo "1. 管理私钥"
        echo "2. 选择跨链方向"
        echo "3. 开启 Telegram 通知"
        echo "4. 删除脚本"
        echo "5. 启动跨链脚本和余额查询"
        echo "6. 退出"
        echo -e "${CYAN}请输入选项（1-6）：${NC}"
        read -p "> " choice
        case $choice in
            1)
                while true; do
                    banner
                    echo -e "${CYAN}私钥管理：${NC}"
                    echo "1. 添加私钥"
                    echo "2. 删除私钥"
                    echo "3. 返回"
                    echo -e "${CYAN}请输入选项（1-3）：${NC}"
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
            6) echo -e "${GREEN}退出脚本！${NC}"; exit 0 ;;
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
