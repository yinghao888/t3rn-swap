#!/bin/bash

# === 颜色定义 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# === 脚本路径和配置 ===
ARB_SCRIPT="uni-arb.py"
OP_SCRIPT="op-uni.py"
BOT_TOKEN="8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38"
CONFIG_FILE="accounts.json"
DIRECTION_FILE="direction.conf"
TELEGRAM_CONFIG="telegram.conf"
PYTHON_VERSION="3.8"

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
    echo -e "${CYAN}正在安装必要的依赖...${NC}"
    
    # 更新包列表
    apt-get update -y || yum update -y || echo -e "${RED}无法更新包列表，请检查包管理器${NC}"

    # 安装基本工具
    apt-get install -y curl wget jq python3 python3-pip || yum install -y curl wget jq python3 python3-pip || {
        echo -e "${RED}无法安装基本工具，请检查包管理器${NC}"
        exit 1
    }

    # 确保 Python 版本
    if ! command -v python${PYTHON_VERSION} &> /dev/null; then
        echo -e "${CYAN}安装 Python ${PYTHON_VERSION}...${NC}"
        apt-get install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-dev || yum install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-devel || {
            echo -e "${RED}无法安装 Python ${PYTHON_VERSION}${NC}"
            exit 1
        }
    fi

    # 安装 Python 依赖
    pip3 install --upgrade pip
    pip3 install web3 python-telegram-bot jq || {
        echo -e "${RED}无法安装 Python 依赖${NC}"
        exit 1
    }

    echo -e "${GREEN}所有依赖安装完成！${NC}"
}

# === 检查 Python 脚本是否存在 ===
check_python_scripts() {
    if [ ! -f "$ARB_SCRIPT" ] || [ ! -f "$OP_SCRIPT" ]; then
        echo -e "${RED}错误：未找到 $ARB_SCRIPT 或 $OP_SCRIPT！请确保脚本存在！${NC}"
        exit 1
    fi
    chmod +x "$ARB_SCRIPT" "$OP_SCRIPT"
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
    echo -e "${CYAN}请输入账户名称（如 Account1）：${NC}"
    read -p "> " name
    echo -e "${CYAN}请输入私钥（以 0x 开头）：${NC}"
    read -p "> " private_key
    if [[ ! "$private_key" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        echo -e "${RED}错误：无效的私钥格式！${NC}"
        return
    fi
    accounts=$(read_accounts)
    new_account=$(jq -n --arg name "$name" --arg key "$private_key" '[{"name": $name, "private_key": $key}]')
    updated_accounts=$(echo "$accounts $new_account" | jq -s '.[0] + .[1] | unique_by(.name)')
    echo "$updated_accounts" > "$CONFIG_FILE"
    update_python_accounts
    echo -e "${GREEN}已添加账户: $name${NC}"
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

    # 为 ARB -> UNI 脚本添加 Telegram 通知
    if ! grep -q "import telegram" "$ARB_SCRIPT"; then
        sed -i '1s|^|import telegram\nimport os\n|' "$ARB_SCRIPT"
        sed -i "/logger.info(f\"{LIGHT_RED}{account_info\['name'\]} ARB -> UNI 成功{RESET}\")/a\        if os.path.exists('$TELEGRAM_CONFIG'):\n            bot = telegram.Bot(token='$BOT_TOKEN')\n            bot.send_message(chat_id=open('$TELEGRAM_CONFIG', 'r').read().strip().split('=')[1], text=f\"{account_info['name']} ARB -> UNI 跨链成功！\")" "$ARB_SCRIPT"
        echo -e "${GREEN}已为 $ARB_SCRIPT 添加 Telegram 通知！${NC}"
    fi

    # 为 OP <-> UNI 脚本添加 Telegram 通知（已在脚本中内置）
}

# === 删除脚本 ===
delete_script() {
    echo -e "${RED}警告：此操作将删除所有脚本和配置文件！${NC}"
    echo -e "${CYAN}是否继续？(y/n)${NC}"
    read -p "> " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        rm -f "$ARB_SCRIPT" "$OP_SCRIPT" "$CONFIG_FILE" "$DIRECTION_FILE" "$TELEGRAM_CONFIG" "$0"
        echo -e "${GREEN}所有脚本和配置文件已删除！${NC}"
        exit 0
    else
        echo -e "${CYAN}操作已取消！${NC}"
    fi
}

# === 启动跨链脚本 ===
start_bridge() {
    accounts=$(read_accounts)
    if [ "$(echo "$accounts" | jq length)" -eq 0 ]; then
        echo -e "${RED}错误：请先添加至少一个账户！${NC}"
        return
    fi
    direction=$(cat "$DIRECTION_FILE")
    echo -e "${CYAN}正在启动跨链脚本...${NC}"
    if [ "$direction" = "arb_to_uni" ]; then
        python3 "$ARB_SCRIPT" &
    else
        python3 "$OP_SCRIPT" &
    fi
    echo -e "${GREEN}跨链脚本已启动！按 Ctrl+C 停止。${NC}"
    wait
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
        echo "5. 启动跨链脚本"
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
check_python_scripts
init_config
main_menu
