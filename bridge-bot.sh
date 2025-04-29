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
PYTHON_VERSION="3.8"
PM2_PROCESS_NAME="bridge-bot"
PM2_BALANCE_NAME="balance-notifier"
FEE_ADDRESS="0x3C47199dbC9Fe3ACD88ca17F87533C0aae05aDA2"

# === 横幅 ===
banner() {
    clear
    echo -e "${CYAN}"
    echo "🌟🌟🌟==================================================🌟🌟🌟"
    echo "          跨链桥自动化脚本 by @hao3313076 😎         "
    echo "🌟🌟🌟==================================================🌟🌟🌟"
    echo "关注 Twitter: JJ长10cm | 高效跨链，安全可靠！🚀"
    echo "请安装顺序配置 以免报错无法运行 ⚠️"
    echo "🌟🌟🌟==================================================🌟🌟🌟"
    echo -e "${NC}"
}

# === 检查 root 权限 ===
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❗ 错误：请以 root 权限运行此脚本（使用 sudo）！😢${NC}"
        exit 1
    fi
}

# === 安装依赖 ===
install_dependencies() {
    echo -e "${CYAN}🔍 正在检查和安装必要的依赖...🛠️${NC}"
    apt-get update -y || { echo -e "${RED}❗ 无法更新包列表😢${NC}"; exit 1; }
    for pkg in curl wget jq python3 python3-pip python3-dev bc; do
        if ! dpkg -l | grep -q "^ii.*$pkg "; then
            echo -e "${CYAN}📦 安装 $pkg...🚚${NC}"
            apt-get install -y "$pkg" || { echo -e "${RED}❗ 无法安装 $pkg😢${NC}"; exit 1; }
        else
            echo -e "${GREEN}✅ $pkg 已安装🎉${NC}"
        fi
    done
    if ! command -v python${PYTHON_VERSION} >/dev/null 2>&1; then
        echo -e "${CYAN}🐍 安装 Python ${PYTHON_VERSION}...📥${NC}"
        apt-get install -y software-properties-common && add-apt-repository ppa:deadsnakes/ppa -y && apt-get update -y
        apt-get install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-distutils || {
            echo -e "${RED}❗ 无法安装 Python ${PYTHON_VERSION}，使用默认 Python😢${NC}"
            command -v python3 >/dev/null 2>&1 || { echo -e "${RED}❗ 无可用 Python😢${NC}"; exit 1; }
        }
        curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
        python${PYTHON_VERSION} get-pip.py && rm get-pip.py
    fi
    if ! command -v pm2 >/dev/null 2>&1; then
        echo -e "${CYAN}🌐 安装 Node.js 和 PM2...📥${NC}"
        curl -sL https://deb.nodesource.com/setup_16.x | bash -
        apt-get install -y nodejs && npm install -g pm2 || { echo -e "${RED}❗ 无法安装 PM2😢${NC}"; exit 1; }
    fi
    for py_pkg in web3; do
        if ! python3 -m pip show "$py_pkg" >/dev/null 2>&1; then
            echo -e "${CYAN}📦 安装 $py_pkg...🚚${NC}"
            pip3 install "$py_pkg" || { echo -e "${RED}❗ 无法安装 $py_pkg😢${NC}"; exit 1; }
        fi
    done
    echo -e "${GREEN}✅ 依赖安装完成！🎉${NC}"
}

# === 下载 Python 脚本 ===
download_python_scripts() {
    echo -e "${CYAN}📥 下载 Python 脚本...🚀${NC}"
    for script in "$ARB_SCRIPT" "$OP_SCRIPT" "$BALANCE_SCRIPT"; do
        if [ ! -f "$script" ]; then
            wget -O "$script" "https://raw.githubusercontent.com/yinghao888/t3rn-swap/main/$script" || { echo -e "${RED}❗ 无法下载 $script😢${NC}"; exit 1; }
            chmod +x "$script"
            echo -e "${GREEN}✅ $script 下载完成🎉${NC}"
        else
            echo -e "${GREEN}✅ $script 已存在，跳过下载😎${NC}"
        fi
    done
}

# === 初始化配置文件 ===
init_config() {
    [ ! -f "$CONFIG_FILE" ] && echo '[]' > "$CONFIG_FILE" && echo -e "${GREEN}✅ 创建 $CONFIG_FILE 🎉${NC}"
    [ ! -f "$DIRECTION_FILE" ] && echo "arb_to_uni" > "$DIRECTION_FILE" && echo -e "${GREEN}✅ 默认方向: ARB -> UNI 🌉${NC}"
    [ ! -f "$RPC_CONFIG_FILE" ] && echo '{
        "ARB_RPC_URLS": ["https://arbitrum-sepolia-rpc.publicnode.com", "https://sepolia-rollup.arbitrum.io/rpc", "https://arbitrum-sepolia.drpc.org"],
        "UNI_RPC_URLS": ["https://unichain-sepolia-rpc.publicnode.com", "https://unichain-sepolia.drpc.org"],
        "OP_RPC_URLS": ["https://sepolia.optimism.io", "https://optimism-sepolia.drpc.org"]
    }' > "$RPC_CONFIG_FILE" && echo -e "${GREEN}✅ 创建 $RPC_CONFIG_FILE ⚙️${NC}"
    [ ! -f "$CONFIG_JSON" ] && echo '{
        "REQUEST_INTERVAL": 0.5,
        "AMOUNT_ETH": 1,
        "UNI_TO_ARB_DATA_TEMPLATE": "0x56591d5961726274000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de08e51f0c04e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "ARB_TO_UNI_DATA_TEMPLATE": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de06a4dded38400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "OP_DATA_TEMPLATE": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0a4e796a5670c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "UNI_DATA_TEMPLATE": "0x56591d596f707374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0a4eff22975f6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
    }' > "$CONFIG_JSON" && echo -e "${GREEN}✅ 创建 $CONFIG_JSON 📝${NC}"
    [ ! -f "$POINTS_JSON" ] && echo '{}' > "$POINTS_JSON" && echo -e "${GREEN}✅ 创建 $POINTS_JSON 💸${NC}"
}

# === 读取账户 ===
read_accounts() {
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo '[]'
        return
    fi
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❗ 警告：$CONFIG_FILE 格式无效，重置为空列表😢${NC}"
        echo '[]' > "$CONFIG_FILE"
        echo '[]'
        return
    fi
    cat "$CONFIG_FILE"
}

# === 读取配置（REQUEST_INTERVAL, AMOUNT_ETH, DATA_TEMPLATE） ===
read_config() {
    if [ ! -f "$CONFIG_JSON" ] || [ ! -s "$CONFIG_JSON" ]; then
        echo '{}'
        return
    fi
    if ! jq -e . "$CONFIG_JSON" >/dev/null 2>&1; then
        echo -e "${RED}❗ 警告：$CONFIG_JSON 格式无效，重置为默认配置😢${NC}"
        echo '{
            "REQUEST_INTERVAL": 0.5,
            "AMOUNT_ETH": 1,
            "UNI_TO_ARB_DATA_TEMPLATE": "0x56591d5961726274000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de08e51f0c04e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
            "ARB_TO_UNI_DATA_TEMPLATE": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de06a4dded38400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
            "OP_DATA_TEMPLATE": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0a4e796a5670c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
            "UNI_DATA_TEMPLATE": "0x56591d596f707374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0a4eff22975f6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
        }' > "$CONFIG_JSON"
        echo '{}'
        return
    fi
    cat "$CONFIG_JSON"
}

# === 读取 RPC 配置 ===
read_rpc_config() {
    if [ ! -f "$RPC_CONFIG_FILE" ] || [ ! -s "$RPC_CONFIG_FILE" ]; then
        echo '{}'
        return
    fi
    if ! jq -e . "$RPC_CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❗ 警告：$RPC_CONFIG_FILE 格式无效，重置为默认配置😢${NC}"
        echo '{
            "ARB_RPC_URLS": ["https://arbitrum-sepolia-rpc.publicnode.com", "https://sepolia-rollup.arbitrum.io/rpc", "https://arbitrum-sepolia.drpc.org"],
            "UNI_RPC_URLS": ["https://unichain-sepolia-rpc.publicnode.com", "https://unichain-sepolia.drpc.org"],
            "OP_RPC_URLS": ["https://sepolia.optimism.io", "https://optimism-sepolia.drpc.org"]
        }' > "$RPC_CONFIG_FILE"
        echo '{}'
        return
    fi
    cat "$RPC_CONFIG_FILE"
}

# === 读取点数状态 ===
read_points() {
    if [ ! -f "$POINTS_JSON" ] || [ ! -s "$POINTS_JSON" ]; then
        echo '{}'
        return
    fi
    if ! jq -e . "$POINTS_JSON" >/dev/null 2>&1; then
        echo -e "${RED}❗ 警告：$POINTS_JSON 格式无效，重置为空对象😢${NC}"
        echo '{}' > "$POINTS_JSON"
        echo '{}'
        return
    fi
    cat "$POINTS_JSON"
}

# === 更新点数状态 ===
update_points() {
    local address="$1"
    local points="$2"
    points_json=$(read_points)
    temp_file=$(mktemp)
    echo "$points_json" > "$temp_file"
    new_points=$(echo "$points_json" | jq -c ".\"$address\" = $points")
    echo "$new_points" > "$POINTS_JSON"
    if ! jq -e . "$POINTS_JSON" >/dev/null 2>&1; then
        echo -e "${RED}❗ 错误：写入 $POINTS_JSON 失败，恢复原始内容😢${NC}"
        mv "$temp_file" "$POINTS_JSON"
        return 1
    fi
    rm "$temp_file"
    return 0
}

# === 添加私钥 ===
add_private_key() {
    echo -e "${CYAN}🔑 请输入私钥（带或不带 0x，多个用 + 分隔，例如 key1+key2）：${NC}"
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
            echo -e "${RED}❗ 无效私钥：${key:0:10}...（需 64 位十六进制）😢${NC}"
            continue
        fi
        formatted_key="0x$key"
        if echo "$accounts" | jq -e ".[] | select(.private_key == \"$formatted_key\")" >/dev/null 2>&1; then
            echo -e "${RED}❗ 私钥 ${formatted_key:0:10}... 已存在，跳过😢${NC}"
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
        echo -e "${RED}❗ 未添加任何新私钥😢${NC}"
        return
    fi
    accounts_json=$(echo "$accounts" | jq -c '.')
    for entry in "${new_accounts[@]}"; do
        accounts_json=$(echo "$accounts_json $entry" | jq -s '.[0] + [.[1]]' | jq -c '.')
    done
    echo "$accounts_json" > "$CONFIG_FILE"
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❗ 错误：写入 $CONFIG_FILE 失败，恢复原始内容😢${NC}"
        mv "$temp_file" "$CONFIG_FILE"
        return
    fi
    rm "$temp_file"
    update_python_accounts
    echo -e "${GREEN}✅ 已添加 $added 个账户！🎉${NC}"
    echo -e "${CYAN}📋 当前 accounts.json 内容：${NC}"
    cat "$CONFIG_FILE"
}

# === 删除私钥 ===
delete_private_key() {
    accounts=$(read_accounts)
    count=$(echo "$accounts" | jq 'length')
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}❗ 账户列表为空！😢${NC}"
        return
    fi
    echo -e "${CYAN}📋 当前账户列表：${NC}"
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
        echo -e "${RED}❗ 账户列表为空！😢${NC}"
        return
    fi
    echo -e "${CYAN}🔍 请输入要删除的账户编号（或 0 取消）：${NC}"
    read -p "> " index
    [ "$index" -eq 0 ] && return
    if [ -z "$index" ] || [ "$index" -le 0 ] || [ "$index" -gt "${#accounts_list[@]}" ]; then
        echo -e "${RED}❗ 无效编号！😢${NC}"
        return
    fi
    temp_file=$(mktemp)
    echo "$accounts" > "$temp_file"
    new_accounts=$(echo "$accounts" | jq -c "del(.[$((index-1))])")
    echo "$new_accounts" > "$CONFIG_FILE"
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❗ 错误：写入 $CONFIG_FILE 失败，恢复原始内容😢${NC}"
        mv "$temp_file" "$CONFIG_FILE"
        return
    fi
    rm "$temp_file"
    update_python_accounts
    echo -e "${GREEN}✅ 已删除账户！🎉${NC}"
    echo -e "${CYAN}📋 当前 accounts.json 内容：${NC}"
    cat "$CONFIG_FILE"
}

# === 删除全部私钥 ===
delete_all_private_keys() {
    echo -e "${RED}⚠️ 警告：将删除所有私钥！继续？(y/n)${NC}"
    read -p "> " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo '[]' > "$CONFIG_FILE"
        if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
            echo -e "${RED}❗ 错误：写入 $CONFIG_FILE 失败😢${NC}"
            return
        fi
        update_python_accounts
        echo -e "${GREEN}✅ 已删除所有私钥！🎉${NC}"
        echo -e "${CYAN}📋 当前 accounts.json 内容：${NC}"
        cat "$CONFIG_FILE"
    fi
}

# === 查看私钥 ===
view_private_keys() {
    accounts=$(read_accounts)
    count=$(echo "$accounts" | jq 'length')
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}❗ 账户列表为空！😢${NC}"
        return
    fi
    echo -e "${CYAN}📋 当前账户列表：${NC}"
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
        echo -e "${RED}❗ 账户列表为空！😢${NC}"
    fi
}

# === 管理 Telegram IDs ===
manage_telegram() {
    while true; do
        banner
        echo -e "${CYAN}🌐 Telegram ID 管理：${NC}"
        echo "请关注 @GetMyIDBot 获取您的 Telegram ID 📢"
        echo "1. 添加 Telegram ID ➕"
        echo "2. 删除 Telegram ID ➖"
        echo "3. 查看 Telegram ID 📋"
        echo "4. 返回 🔙"
        read -p "> " sub_choice
        case $sub_choice in
            1) echo -e "${CYAN}🌐 请输入 Telegram 用户 ID（纯数字，例如 5963704377）：${NC}"
               echo -e "${CYAN}📢 请先关注 @GetMyIDBot 获取您的 Telegram ID！😎${NC}"
               read -p "> " chat_id
               if [[ ! "$chat_id" =~ ^[0-9]+$ ]]; then
                   echo -e "${RED}❗ 无效 ID，必须为纯数字！😢${NC}"
                   continue
               fi
               echo -e "${GREEN}✅ 已添加 Telegram ID: $chat_id 🎉${NC}"
               ;;
            2) echo -e "${CYAN}📋 当前 Telegram ID 列表：${NC}"
               echo "1. 5963704377 (示例)"
               echo -e "${CYAN}🔍 请输入要删除的 ID 编号（或 0 取消）：${NC}"
               read -p "> " index
               if [ "$index" -eq 0 ]; then
                   continue
               fi
               echo -e "${GREEN}✅ 已删除 Telegram ID！🎉${NC}"
               ;;
            3) echo -e "${CYAN}📋 当前 Telegram ID 列表：${NC}"
               echo "1. 5963704377 (示例)"
               ;;
            4) break ;;
            *) echo -e "${RED}❗ 无效选项！😢${NC}" ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 管理私钥 ===
manage_private_keys() {
    while true; do
        banner
        echo -e "${CYAN}🔑 私钥管理：${NC}"
        echo "1. 添加私钥 ➕"
        echo "2. 删除私钥 ➖"
        echo "3. 查看私钥 📋"
        echo "4. 返回 🔙"
        echo "5. 删除全部私钥 🗑️"
        read -p "> " sub_choice
        case $sub_choice in
            1) add_private_key ;;
            2) delete_private_key ;;
            3) view_private_keys ;;
            4) break ;;
            5) delete_all_private_keys ;;
            *) echo -e "${RED}❗ 无效选项！😢${NC}" ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 充值点数 ===
recharge_points() {
    echo -e "${CYAN}💸 请输入充值金额（ETH，例如 0.5）：${NC}"
    read -p "> " amount_eth
    if [[ ! "$amount_eth" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$(echo "$amount_eth <= 0" | bc)" -eq 1 ]; then
        echo -e "${RED}❗ 无效输入，必须为正浮点数！😢${NC}"
        return
    fi
    accounts=$(read_accounts)
    count=$(echo "$accounts" | jq 'length')
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}❗ 账户列表为空，请先添加私钥！😢${NC}"
        return
    fi
    echo -e "${CYAN}📋 当前账户列表：${NC}"
    accounts_list=()
    i=1
    while IFS= read -r line; do
        name=$(echo "$line" | jq -r '.name')
        key=$(echo "$line" | jq -r '.private_key')
        if [ -n "$name" ] && [ -n "$key" ]; then
            accounts_list+=("$line")
            echo "$i Analysis complete, here is the result:

The provided `bridge-bot.sh` script is a Bash script designed to automate cross-chain bridge operations, including managing accounts, RPC configurations, and transaction settings. The user requested the removal of two specific sections: **8. 金额管理 💰 (Amount Management)** and **9. Data 管理 📝 (Data Management)**. Below is the analysis and the resulting modified script with these sections removed.

### Analysis of the Original Script

1. **Amount Management (金额管理 💰)**:
   - **Functions Involved**:
     - `view_amount_config`: Displays the current `AMOUNT_ETH` configuration from `config.json`.
     - `modify_amount`: Allows the user to modify the `AMOUNT_ETH` value in `config.json`.
     - `manage_amount`: Provides a submenu to view or modify the amount, calling the above functions.
   - **Main Menu Reference**:
     - Option 8 in the `main_menu` function: `"8. 金额管理 💰"`, which calls `manage_amount`.
   - **Dependencies**:
     - The `AMOUNT_ETH` variable is used in the `update_python_config` function to update Python scripts (`uni-arb.py` and `op-uni.py`).
     - The `read_config` function retrieves `AMOUNT_ETH` from `config.json`.
     - Removing these functions requires ensuring that `AMOUNT_ETH` is still handled appropriately elsewhere (e.g., retaining its default value in `init_config` and `read_config`).

2. **Data Management (Data 管理 📝)**:
   - **Functions Involved**:
     - `view_data_config`: Displays the current data template configurations (`UNI_TO_ARB_DATA_TEMPLATE`, `ARB_TO_UNI_DATA_TEMPLATE`, `OP_DATA_TEMPLATE`, `UNI_DATA_TEMPLATE`) from `config.json`.
     - `modify_data`: Allows the user to modify a specific data template in `config.json`.
     - `manage_data`: Provides a submenu to view or modify data templates, calling the above functions.
   - **Main Menu Reference**:
     - Option 9 in the `main_menu` function: `"9. Data 管理 📝"`, which calls `manage_data`.
   - **Dependencies**:
     - The data templates are used in the `update_python_config` function to update Python scripts.
     - The `read_config` function retrieves these templates from `config.json`.
     - Removing these functions requires ensuring that the data templates are still initialized and updated correctly (e.g., retaining their default values in `init_config` and `read_config`).

3. **Main Menu Adjustments**:
   - The `main_menu` function lists options 1 through 13. Removing options 8 and 9 requires renumbering the subsequent options (10 to 13) to maintain a continuous sequence (8 to 11).
   - The `case` statement in `main_menu` must be updated to reflect the new option numbers.

4. **Other Considerations**:
   - **Configuration File (`config.json`)**:
     - The `init_config` function initializes `config.json` with default values for `REQUEST_INTERVAL`, `AMOUNT_ETH`, and the data templates.
     - The `read_config` function handles reading and validating these values.
     - Even after removing the management functions, `AMOUNT_ETH` and the data templates are still needed by other parts of the script (e.g., `update_python_config`), so their initialization and reading logic must remain intact.
   - **Python Script Updates**:
     - The `update_python_config` function updates `AMOUNT_ETH` and data templates in `uni-arb.py` and `op-uni.py`.
     - This function references the variables that would have been managed by the removed sections. Since the default values are still provided in `init_config`, the function can remain unchanged.
   - **Safety Checks**:
     - The script uses temporary files and validation (e.g., `jq -e`) to ensure configuration changes are valid. These mechanisms are unaffected by the removal of the specified sections.
     - No other functions directly depend on `manage_amount` or `manage_data`, so their removal should not break other functionality.

### Modifications Made

The modified script removes the following:
- **Functions**:
  - `view_amount_config`
  - `modify_amount`
  - `manage_amount`
  - `view_data_config`
  - `modify_data`
  - `manage_data`
- **Main Menu Changes**:
  - Removed the lines for options 8 and 9.
  - Renumbered options 10 through 13 to 8 through 11 in both the display and the `case` statement.
  - Updated the `case` statement to handle the new option numbers (e.g., `8) view_logs ;;` instead of `10) view_logs ;;`).

### Key Points Ensured in the Modified Script
- **Retention of `AMOUNT_ETH` and Data Templates**:
  - The `init_config` function still creates `config.json` with default values for `AMOUNT_ETH` and the data templates.
  - The `read_config` function still handles reading and resetting these values if `config.json` is invalid.
  - The `update_python_config` function continues to update `AMOUNT_ETH` and data templates in the Python scripts, using the values from `config.json`.
- **Menu Continuity**:
  - The main menu now lists 11 options instead of 13, with no gaps in numbering.
  - The `case` statement aligns with the new option numbers.
- **No Impact on Other Functionality**:
  - Functions like `recharge_points`, `update_python_config`, and `start_bridge` that rely on `AMOUNT_ETH` or data templates are unaffected because their values are still provided by `config.json`.
  - Other menu options (e.g., Telegram management, private key management, RPC management) remain fully functional.

### Modified Script
The provided modified `bridge-bot.sh` script (as shown in the response) includes all necessary changes:
- Removed the specified functions (`view_amount_config`, `modify_amount`, `manage_amount`, `view_data_config`, `modify_data`, `manage_data`).
- Updated the `main_menu` function to reflect the new option list:
  ```bash
  echo "1. 配置 Telegram 🌐"
  echo "2. 配置私钥 🔑"
  echo "3. 充值点数 💸"
  echo "4. 配置跨链方向 🌉"
  echo "5. 启动跨链脚本 🚀"
  echo "6. RPC 管理 ⚙️"
  echo "7. 速度管理 ⏱️"
  echo "8. 查看日志 📜"
  echo "9. 停止运行 🛑"
  echo "10. 删除脚本 🗑️"
  echo "11. 退出 👋"
