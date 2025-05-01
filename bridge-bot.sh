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
CONFIG_FILE="accounts.json"
DIRECTION_FILE="direction.conf"
RPC_CONFIG_FILE="rpc_config.json"
CONFIG_JSON="config.json"
POINTS_JSON="points.json"
PYTHON_VERSION="3"
PM2_PROCESS_NAME="bridge-bot"
PM2_BALANCE_NAME="balance-notifier"
FEE_ADDRESS="0x3C47199dbC9Fe3ACD88ca17F87533C0aae05aDA2"
TELEGRAM_BOT_TOKEN="8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38"
TELEGRAM_CHAT_ID=""
POINTS_HASH_FILE="points.hash"

# === 横幅 ===
banner() {
    clear
    cat << EOF
${CYAN}
🌟🌟🌟==================================================🌟🌟🌟
          跨链桥自动化脚本 by @hao3313076 😎         
🌟🌟🌟==================================================🌟🌟🌟
关注 Twitter: JJ长10cm | 高效跨链，安全可靠！🚀
请安装顺序配置 以免报错无法运行 ⚠️
🌟🌟🌟==================================================🌟🌟🌟
${NC}
EOF
}

# === 主菜单 ===
main_menu() {
    while true; do
        banner
        cat << EOF
${CYAN}🔧 主菜单：${NC}
1. 管理私钥 🔑
2. 管理 RPC ⚙️
3. 管理速度 ⏱️
4. 管理 Telegram 🌐
5. 选择跨链方向 🌉
6. 开始运行 🚀
7. 停止运行 🛑
8. 查看日志 📜
9. 充值点数 💰
10. 删除脚本 🗑️
0. 退出 👋
EOF
        read -p "> " choice
        case $choice in
            1) manage_private_keys ;;
            2) manage_rpc ;;
            3) manage_speed ;;
            4) manage_telegram ;;
            5) select_direction ;;
            6) start_running ;;
            7) stop_running ;;
            8) view_logs ;;
            9) recharge_points ;;
            10) delete_script ;;
            0) 
                echo -e "${GREEN}👋 感谢使用，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❗ 无效选项！😢${NC}" >&2
                ;;
        esac
    done
}

# === 管理私钥 ===
manage_private_keys() {
    validate_points_file
    while true; do
        banner
        cat << EOF
${CYAN}🔑 私钥管理：${NC}
1. 添加私钥 ➕
2. 删除私钥 ➖
3. 查看私钥 📋
4. 返回 🔙
5. 删除全部私钥 🗑️
EOF
        read -p "> " sub_choice
        case $sub_choice in
            1) add_private_key ;;
            2) delete_private_key ;;
            3) view_private_keys ;;
            4) break ;;
            5) delete_all_private_keys ;;
            *)
                echo -e "${RED}❗ 无效选项！😢${NC}" >&2
                ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 管理 RPC ===
manage_rpc() {
    validate_points_file
    while true; do
        banner
        cat << EOF
${CYAN}⚙️ RPC 管理：${NC}
1. 查看当前 RPC 📋
2. 修改 RPC ⚙️
3. 返回 🔙
EOF
        read -p "> " sub_choice
        case $sub_choice in
            1) view_rpc_config ;;
            2) modify_rpc ;;
            3) break ;;
            *)
                echo -e "${RED}❗ 无效选项！😢${NC}" >&2
                ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 管理速度 ===
manage_speed() {
    validate_points_file
    while true; do
        banner
        cat << EOF
${CYAN}⏱️ 速度管理：${NC}
1. 查看当前速度 📋
2. 修改速度 ⏱️
3. 返回 🔙
EOF
        read -p "> " sub_choice
        case $sub_choice in
            1) view_speed_config ;;
            2) modify_speed ;;
            3) break ;;
            *)
                echo -e "${RED}❗ 无效选项！😢${NC}" >&2
                ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 管理 Telegram ===
manage_telegram() {
    validate_points_file
    while true; do
        banner
        cat << EOF
${CYAN}🌐 Telegram ID 管理：${NC}
请关注 @GetMyIDBot 获取您的 Telegram ID 📢
1. 添加 Telegram ID ➕
2. 删除 Telegram ID ➖
3. 查看 Telegram ID 📋
4. 返回 🔙
EOF
        read -p "> " sub_choice
        case $sub_choice in
            1)
                echo -e "${CYAN}🌐 请输入 Telegram 用户 ID（纯数字，例如 5963704377）：${NC}"
                echo -e "${CYAN}📢 请先关注 @GetMyIDBot 获取您的 Telegram ID！😎${NC}"
                read -p "> " chat_id
                if [[ ! "$chat_id" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}❗ 无效 ID，必须为纯数字！😢${NC}" >&2
                    continue
                fi
                TELEGRAM_CHAT_ID="$chat_id"
                echo "$chat_id" > telegram.conf
                echo -e "${GREEN}✅ 已添加 Telegram ID: $chat_id 🎉${NC}"
                ;;
            2)
                echo -e "${CYAN}📋 当前 Telegram ID：${NC}"
                if [ -z "$TELEGRAM_CHAT_ID" ]; then
                    echo "无 Telegram ID"
                else
                    echo "1. $TELEGRAM_CHAT_ID"
                fi
                echo -e "${CYAN}🔍 请输入要删除的 ID 编号（或 0 取消）：${NC}"
                read -p "> " index
                if [ "$index" -eq 0 ]; then
                    continue
                fi
                TELEGRAM_CHAT_ID=""
                rm -f telegram.conf
                echo -e "${GREEN}✅ 已删除 Telegram ID！🎉${NC}"
                ;;
            3)
                echo -e "${CYAN}📋 当前 Telegram ID：${NC}"
                if [ -z "$TELEGRAM_CHAT_ID" ]; then
                    echo "无 Telegram ID"
                else
                    echo "1. $TELEGRAM_CHAT_ID"
                fi
                ;;
            4) break ;;
            *)
                echo -e "${RED}❗ 无效选项！😢${NC}" >&2
                ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 主函数 ===
main() {
    # 检查 root 权限
    check_root

    # 初始化配置
    init_config

    # 安装依赖
    install_dependencies

    # 下载 Python 脚本
    download_python_scripts

    # 启动主菜单
    main_menu
}

# 启动主函数
main "$@"
