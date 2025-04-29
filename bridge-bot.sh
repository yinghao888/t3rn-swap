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
RPC_CONFIG_FILE="rpc_config.json"
PYTHON_VERSION="3.8"
PM2_PROCESS_NAME="bridge-bot"
PM2_BALANCE_NAME="balance-notifier"
CONFIG_JSON="config.json"

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
    for pkg in curl wget jq python3 python3-pip python3-dev; do
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
        "REQUEST_INTERVAL": 1,
        "AMOUNT_ETH": 1,
        "UNI_TO_ARB_DATA_TEMPLATE": "0x56591d5961726274000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de08e51f0c04e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "ARB_TO_UNI_DATA_TEMPLATE": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de06a4dded38400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "OP_DATA_TEMPLATE": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0a4e796a5670c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "UNI_DATA_TEMPLATE": "0x56591d596f707374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0a4eff22975f6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
    }' > "$CONFIG_JSON" && echo -e "${GREEN}✅ 创建 $CONFIG_JSON 📝${NC}"
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
            "REQUEST_INTERVAL": 1,
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

# === 查看当前 RPC ===
view_rpc_config() {
    rpc_config=$(read_rpc_config)
    echo -e "${CYAN}⚙️ 当前 RPC 配置：${NC}"
    echo -e "${CYAN}📋 Arbitrum Sepolia RPC:${NC}"
    echo "$rpc_config" | jq -r '.ARB_RPC_URLS[]' | nl -w2 -s '. '
    echo -e "${CYAN}📋 Unichain Sepolia RPC:${NC}"
    echo "$rpc_config" | jq -r '.UNI_RPC_URLS[]' | nl -w2 -s '. '
    echo -e "${CYAN}📋 Optimism Sepolia RPC:${NC}"
    echo "$rpc_config" | jq -r '.OP_RPC_URLS[]' | nl -w2 -s '. '
}

# === 添加 RPC ===
add_rpc() {
    echo -e "${CYAN}⚙️ 请选择链类型：${NC}"
    echo "1. Arbitrum Sepolia (ARB) 🌟"
    echo "2. Unichain Sepolia (UNI) 🌟"
    echo "3. Optimism Sepolia (OP) 🌟"
    read -p "> " chain_choice
    case $chain_choice in
        1) chain_key="ARB_RPC_URLS" ;;
        2) chain_key="UNI_RPC_URLS" ;;
        3) chain_key="OP_RPC_URLS" ;;
        *) echo -e "${RED}❗ 无效链类型！😢${NC}"; return ;;
    esac
    echo -e "${CYAN}🌐 请输入 RPC URL（例如 https://rpc.example.com）：${NC}"
    read -p "> " rpc_url
    if [[ ! "$rpc_url" =~ ^https?:// ]]; then
        echo -e "${RED}❗ 无效 URL，必须以 http:// 或 https:// 开头！😢${NC}"
        return
    fi
    rpc_config=$(read_rpc_config)
    temp_file=$(mktemp)
    echo "$rpc_config" > "$temp_file"
    new_config=$(echo "$rpc_config" | jq -c ".$chain_key += [\"$rpc_url\"]")
    echo "$new_config" > "$RPC_CONFIG_FILE"
    if ! jq -e . "$RPC_CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❗ 错误：写入 $RPC_CONFIG_FILE 失败，恢复原始内容😢${NC}"
        mv "$temp_file" "$RPC_CONFIG_FILE"
        return
    fi
    rm "$temp_file"
    update_python_rpc
    echo -e "${GREEN}✅ 已添加 RPC: $rpc_url 到 $chain_key 🎉${NC}"
}

# === 删除 RPC ===
delete_rpc() {
    echo -e "${CYAN}⚙️ 请选择链类型：${NC}"
    echo "1. Arbitrum Sepolia (ARB) 🌟"
    echo "2. Unichain Sepolia (UNI) 🌟"
    echo "3. Optimism Sepolia (OP) 🌟"
    read -p "> " chain_choice
    case $chain_choice in
        1) chain_key="ARB_RPC_URLS" ;;
        2) chain_key="UNI_RPC_URLS" ;;
        3) chain_key="OP_RPC_URLS" ;;
        *) echo -e "${RED}❗ 无效链类型！😢${NC}"; return ;;
    esac
    rpc_config=$(read_rpc_config)
    count=$(echo "$rpc_config" | jq ".$chain_key | length")
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}❗ $chain_key RPC 列表为空！😢${NC}"
        return
    fi
    echo -e "${CYAN}📋 当前 $chain_key RPC 列表：${NC}"
    echo "$rpc_config" | jq -r ".$chain_key[]" | nl -w2 -s '. '
    echo -e "${CYAN}🔍 请输入要删除的 RPC 编号（或 0 取消）：${NC}"
    read -p "> " index
    [ "$index" -eq 0 ] && return
    if [ -z "$index" ] || [ "$index" -le 0 ] || [ "$index" -gt "$count" ]; then
        echo -e "${RED}❗ 无效编号！😢${NC}"
        return
    fi
    temp_file=$(mktemp)
    echo "$rpc_config" > "$temp_file"
    new_config=$(echo "$rpc_config" | jq -c "del(.$chain_key[$((index-1))])")
    echo "$new_config" > "$RPC_CONFIG_FILE"
    if ! jq -e . "$RPC_CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❗ 错误：写入 $RPC_CONFIG_FILE 失败，恢复原始内容😢${NC}"
        mv "$temp_file" "$RPC_CONFIG_FILE"
        return
    fi
    rm "$temp_file"
    update_python_rpc
    echo -e "${GREEN}✅ 已删除 $chain_key 的 RPC！🎉${NC}"
}

# === 更新 Python 脚本 RPC 配置 ===
update_python_rpc() {
    rpc_config=$(read_rpc_config)
    arb_rpc_str=$(echo "$rpc_config" | jq -r '.ARB_RPC_URLS' | sed 's/"/\\"/g')
    uni_rpc_str=$(echo "$rpc_config" | jq -r '.UNI_RPC_URLS' | sed 's/"/\\"/g')
    op_rpc_str=$(echo "$rpc_config" | jq -r '.OP_RPC_URLS' | sed 's/"/\\"/g')
    for script in "$ARB_SCRIPT" "$OP_SCRIPT"; do
        if [ ! -f "$script" ]; then
            echo -e "${RED}❗ 错误：$script 不存在😢${NC}"
            return
        fi
        if [ ! -w "$script" ]; then
            echo -e "${RED}❗ 错误：$script 不可写😢${NC}"
            return
        fi
    done
    sed -i "/^ARB_RPC_URLS = /c\ARB_RPC_URLS = $arb_rpc_str" "$ARB_SCRIPT"
    sed -i "/^UNI_RPC_URLS = /c\UNI_RPC_URLS = $uni_rpc_str" "$ARB_SCRIPT"
    sed -i "/^OP_RPC_URLS = /c\OP_RPC_URLS = $op_rpc_str" "$OP_SCRIPT"
    sed -i "/^UNI_RPC_URLS = /c\UNI_RPC_URLS = $uni_rpc_str" "$OP_SCRIPT"
    echo -e "${GREEN}✅ 已更新 $ARB_SCRIPT 和 $OP_SCRIPT 的 RPC 配置！🎉${NC}"
    echo -e "${CYAN}📋 当前 $ARB_SCRIPT RPC 内容：${NC}"
    grep "^ARB_RPC_URLS =" "$ARB_SCRIPT"
    grep "^UNI_RPC_URLS =" "$ARB_SCRIPT"
    echo -e "${CYAN}📋 当前 $OP_SCRIPT RPC 内容：${NC}"
    grep "^OP_RPC_URLS =" "$OP_SCRIPT"
    grep "^UNI_RPC_URLS =" "$OP_SCRIPT"
}

# === RPC 管理 ===
manage_rpc() {
    while true; do
        banner
        echo -e "${CYAN}⚙️ RPC 管理：${NC}"
        echo "1. 查看当前 RPC 📋"
        echo "2. 添加 RPC ➕"
        echo "3. 删除 RPC ➖"
        echo "4. 返回 🔙"
        read -p "> " sub_choice
        case $sub_choice in
            1) view_rpc_config ;;
            2) add_rpc ;;
            3) delete_rpc ;;
            4) break ;;
            *) echo -e "${RED}❗ 无效选项！😢${NC}" ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 查看当前速度 ===
view_speed_config() {
    config=$(read_config)
    request_interval=$(echo "$config" | jq -r '.REQUEST_INTERVAL')
    echo -e "${CYAN}⏱️ 当前速度配置：${NC}"
    echo "REQUEST_INTERVAL: $request_interval 秒"
}

# === 修改速度 ===
modify_speed() {
    echo -e "${CYAN}⏱️ 请输入新的 REQUEST_INTERVAL（正整数，单位：秒）：${NC}"
    read -p "> " request_interval
    if [[ ! "$request_interval" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RED}❗ 无效输入，必须为正整数！😢${NC}"
        return
    fi
    config=$(read_config)
    temp_file=$(mktemp)
    echo "$config" > "$temp_file"
    new_config=$(echo "$config" | jq -c ".REQUEST_INTERVAL = $request_interval")
    echo "$new_config" > "$CONFIG_JSON"
    if ! jq -e . "$CONFIG_JSON" >/dev/null 2>&1; then
        echo -e "${RED}❗ 错误：写入 $CONFIG_JSON 失败，恢复原始内容😢${NC}"
        mv "$temp_file" "$CONFIG_JSON"
        return
    fi
    rm "$temp_file"
    update_python_config
    echo -e "${GREEN}✅ 已更新 REQUEST_INTERVAL 为 $request_interval 秒！🎉${NC}"
}

# === 速度管理 ===
manage_speed() {
    while true; do
        banner
        echo -e "${CYAN}⏱️ 速度管理：${NC}"
        echo "1. 查看当前速度 📋"
        echo "2. 修改速度 ⏱️"
        echo "3. 返回 🔙"
        read -p "> " sub_choice
        case $sub_choice in
            1) view_speed_config ;;
            2) modify_speed ;;
            3) break ;;
            *) echo -e "${RED}❗ 无效选项！😢${NC}" ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 查看当前金额 ===
view_amount_config() {
    config=$(read_config)
    amount_eth=$(echo "$config" | jq -r '.AMOUNT_ETH')
    echo -e "${CYAN}💰 当前金额配置：${NC}"
    echo "AMOUNT_ETH: $amount_eth ETH"
}

# === 修改金额 ===
modify_amount() {
    echo -e "${CYAN}💰 请输入新的 AMOUNT_ETH（正浮点数，单位：ETH）：${NC}"
    read -p "> " amount_eth
    if [[ ! "$amount_eth" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$(echo "$amount_eth <= 0" | bc)" -eq 1 ]; then
        echo -e "${RED}❗ 无效输入，必须为正浮点数！😢${NC}"
        return
    fi
    config=$(read_config)
    temp_file=$(mktemp)
    echo "$config" > "$temp_file"
    new_config=$(echo "$config" | jq -c ".AMOUNT_ETH = $amount_eth")
    echo "$new_config" > "$CONFIG_JSON"
    if ! jq -e . "$CONFIG_JSON" >/dev/null 2>&1; then
        echo -e "${RED}❗ 错误：写入 $CONFIG_JSON 失败，恢复原始内容😢${NC}"
        mv "$temp_file" "$CONFIG_JSON"
        return
    fi
    rm "$temp_file"
    update_python_config
    echo -e "${GREEN}✅ 已更新 AMOUNT_ETH 为 $amount_eth ETH！🎉${NC}"
}

# === 金额管理 ===
manage_amount() {
    while true; do
        banner
        echo -e "${CYAN}💰 金额管理：${NC}"
        echo "1. 查看当前金额 📋"
        echo "2. 修改金额 💰"
        echo "3. 返回 🔙"
        read -p "> " sub_choice
        case $sub_choice in
            1) view_amount_config ;;
            2) modify_amount ;;
            3) break ;;
            *) echo -e "${RED}❗ 无效选项！😢${NC}" ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 查看当前 Data 模板 ===
view_data_config() {
    config=$(read_config)
    echo -e "${CYAN}📝 当前 Data 模板配置：${NC}"
    echo -e "${CYAN}📋 UNI_TO_ARB_DATA_TEMPLATE:${NC}"
    echo "$(echo "$config" | jq -r '.UNI_TO_ARB_DATA_TEMPLATE' | head -c 50)..."
    echo -e "${CYAN}📋 ARB_TO_UNI_DATA_TEMPLATE:${NC}"
    echo "$(echo "$config" | jq -r '.ARB_TO_UNI_DATA_TEMPLATE' | head -c 50)..."
    echo -e "${CYAN}📋 OP_DATA_TEMPLATE:${NC}"
    echo "$(echo "$config" | jq -r '.OP_DATA_TEMPLATE' | head -c 50)..."
    echo -e "${CYAN}📋 UNI_DATA_TEMPLATE:${NC}"
    echo "$(echo "$config" | jq -r '.UNI_DATA_TEMPLATE' | head -c 50)..."
}

# === 修改 Data 模板 ===
modify_data() {
    echo -e "${CYAN}📝 请选择要修改的 Data 模板：${NC}"
    echo "1. UNI_TO_ARB_DATA_TEMPLATE 🌟"
    echo "2. ARB_TO_UNI_DATA_TEMPLATE 🌟"
    echo "3. OP_DATA_TEMPLATE 🌟"
    echo "4. UNI_DATA_TEMPLATE 🌟"
    read -p "> " template_choice
    case $template_choice in
        1) template_key="UNI_TO_ARB_DATA_TEMPLATE" ;;
        2) template_key="ARB_TO_UNI_DATA_TEMPLATE" ;;
        3) template_key="OP_DATA_TEMPLATE" ;;
        4) template_key="UNI_DATA_TEMPLATE" ;;
        *) echo -e "${RED}❗ 无效模板选择！😢${NC}"; return ;;
    esac
    echo -e "${CYAN}📝 请输入新的 $template_key（十六进制字符串，需包含 {address}）：${NC}"
    read -p "> " template_value
    if [[ ! "$template_value" =~ ^0x[0-9a-fA-F]*\{address\}[0-9a-fA-F]*$ ]]; then
        echo -e "${RED}❗ 无效输入，必须为十六进制字符串且包含 {address}！😢${NC}"
        return
    fi
    config=$(read_config)
    temp_file=$(mktemp)
    echo "$config" > "$temp_file"
    new_config=$(echo "$config" | jq -c ".$template_key = \"$template_value\"")
    echo "$new_config" > "$CONFIG_JSON"
    if ! jq -e . "$CONFIG_JSON" >/dev/null 2>&1; then
        echo -e "${RED}❗ 错误：写入 $CONFIG_JSON 失败，恢复原始内容😢${NC}"
        mv "$temp_file" "$CONFIG_JSON"
        return
    fi
    rm "$temp_file"
    update_python_config
    echo -e "${GREEN}✅ 已更新 $template_key！🎉${NC}"
}

# === Data 管理 ===
manage_data() {
    while true; do
        banner
        echo -e "${CYAN}📝 Data 管理：${NC}"
        echo "1. 查看当前 Data 模板 📋"
        echo "2. 修改 Data 模板 📝"
        echo "3. 返回 🔙"
        read -p "> " sub_choice
        case $sub_choice in
            1) view_data_config ;;
            2) modify_data ;;
            3) break ;;
            *) echo -e "${RED}❗ 无效选项！😢${NC}" ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 更新 Python 脚本配置（REQUEST_INTERVAL, AMOUNT_ETH, DATA_TEMPLATE） ===
update_python_config() {
    config=$(read_config)
    request_interval=$(echo "$config" | jq -r '.REQUEST_INTERVAL')
    amount_eth=$(echo "$config" | jq -r '.AMOUNT_ETH')
    uni_to_arb_data=$(echo "$config" | jq -r '.UNI_TO_ARB_DATA_TEMPLATE' | sed 's/"/\\"/g')
    arb_to_uni_data=$(echo "$config" | jq -r '.ARB_TO_UNI_DATA_TEMPLATE' | sed 's/"/\\"/g')
    op_data=$(echo "$config" | jq -r '.OP_DATA_TEMPLATE' | sed 's/"/\\"/g')
    uni_data=$(echo "$config" | jq -r '.UNI_DATA_TEMPLATE' | sed 's/"/\\"/g')
    for script in "$ARB_SCRIPT" "$OP_SCRIPT"; do
        if [ ! -f "$script" ]; then
            echo -e "${RED}❗ 错误：$script 不存在😢${NC}"
            return
        fi
        if [ ! -w "$script" ]; then
            echo -e "${RED}❗ 错误：$script 不可写😢${NC}"
            return
        fi
    done
    sed -i "/^REQUEST_INTERVAL = /c\REQUEST_INTERVAL = $request_interval" "$ARB_SCRIPT"
    sed -i "/^AMOUNT_ETH = /c\AMOUNT_ETH = $amount_eth" "$ARB_SCRIPT"
    sed -i "/^UNI_TO_ARB_DATA_TEMPLATE = /c\UNI_TO_ARB_DATA_TEMPLATE = \"$uni_to_arb_data\"" "$ARB_SCRIPT"
    sed -i "/^ARB_TO_UNI_DATA_TEMPLATE = /c\ARB_TO_UNI_DATA_TEMPLATE = \"$arb_to_uni_data\"" "$ARB_SCRIPT"
    sed -i "/^REQUEST_INTERVAL = /c\REQUEST_INTERVAL = $request_interval" "$OP_SCRIPT"
    sed -i "/^AMOUNT_ETH = /c\AMOUNT_ETH = $amount_eth" "$OP_SCRIPT"
    sed -i "/^OP_DATA_TEMPLATE = /c\OP_DATA_TEMPLATE = \"$op_data\"" "$OP_SCRIPT"
    sed -i "/^UNI_DATA_TEMPLATE = /c\UNI_DATA_TEMPLATE = \"$uni_data\"" "$OP_SCRIPT"
    echo -e "${GREEN}✅ 已更新 $ARB_SCRIPT 和 $OP_SCRIPT 的配置！🎉${NC}"
    echo -e "${CYAN}📋 当前 $ARB_SCRIPT 配置：${NC}"
    grep "^REQUEST_INTERVAL =" "$ARB_SCRIPT"
    grep "^AMOUNT_ETH =" "$ARB_SCRIPT"
    grep "^UNI_TO_ARB_DATA_TEMPLATE =" "$ARB_SCRIPT"
    grep "^ARB_TO_UNI_DATA_TEMPLATE =" "$ARB_SCRIPT"
    echo -e "${CYAN}📋 当前 $OP_SCRIPT 配置：${NC}"
    grep "^REQUEST_INTERVAL =" "$OP_SCRIPT"
    grep "^AMOUNT_ETH =" "$OP_SCRIPT"
    grep "^OP_DATA_TEMPLATE =" "$OP_SCRIPT"
    grep "^UNI_DATA_TEMPLATE =" "$OP_SCRIPT"
}

# === 更新 Python 脚本账户 ===
update_python_accounts() {
    accounts=$(read_accounts)
    accounts_str=$(echo "$accounts" | jq -r '[.[] | {"private_key": .private_key, "name": .name}]' | jq -r '@json')
    if [ -z "$accounts_str" ] || [ "$accounts_str" == "[]" ]; then
        accounts_str="[]"
    fi
    for script in "$ARB_SCRIPT" "$OP_SCRIPT"; do
        if [ ! -f "$script" ]; then
            echo -e "${RED}❗ 错误：$script 不存在😢${NC}"
            return
        fi
        if [ ! -w "$script" ]; then
            echo -e "${RED}❗ 错误：$script 不可写😢${NC}"
            return
        fi
    done
    temp_file=$(mktemp)
    sed "/^ACCOUNTS = \[.*\]/c\ACCOUNTS = $accounts_str" "$ARB_SCRIPT" > "$temp_file"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❗ 错误：更新 $ARB_SCRIPT 失败😢${NC}"
        rm "$temp_file"
        return
    fi
    mv "$temp_file" "$ARB_SCRIPT"
    temp_file=$(mktemp)
    sed "/^ACCOUNTS = \[.*\]/c\ACCOUNTS = $accounts_str" "$OP_SCRIPT" > "$temp_file"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❗ 错误：更新 $OP_SCRIPT 失败😢${NC}"
        rm "$temp_file"
        return
    fi
    mv "$temp_file" "$OP_SCRIPT"
    for script in "$ARB_SCRIPT" "$OP_SCRIPT"; do
        current_accounts=$(grep "^ACCOUNTS =" "$script" | sed 's/ACCOUNTS = //')
        if [ "$current_accounts" != "$accounts_str" ]; then
            echo -e "${RED}❗ 错误：验证 $script 更新失败😢${NC}"
            return
        fi
    done
    echo -e "${GREEN}✅ 已更新 $ARB_SCRIPT 和 $OP_SCRIPT 的账户！🎉${NC}"
    echo -e "${CYAN}📋 当前 $ARB_SCRIPT ACCOUNTS 内容：${NC}"
    grep "^ACCOUNTS =" "$ARB_SCRIPT"
    echo -e "${CYAN}📋 当前 $OP_SCRIPT ACCOUNTS 内容：${NC}"
    grep "^ACCOUNTS =" "$OP_SCRIPT"
}

# === 配置跨链方向 ===
select_direction() {
    echo -e "${CYAN}🌉 请选择跨链方向：${NC}"
    echo "1. ARB -> UNI 🌟"
    echo "2. OP <-> UNI 🌟"
    read -p "> " choice
    case $choice in
        1)
            echo "arb_to_uni" > "$DIRECTION_FILE"
            echo -e "${GREEN}✅ 设置为 ARB -> UNI 🎉${NC}"
            ;;
        2)
            echo "op_to_uni" > "$DIRECTION_FILE"
            echo -e "${GREEN}✅ 设置为 OP <-> UNI 🎉${NC}"
            ;;
        *)
            echo -e "${RED}❗ 无效选项，默认 ARB -> UNI😢${NC}"
            echo "arb_to_uni" > "$DIRECTION_FILE"
            ;;
    esac
}

# === 查看日志 ===
view_logs() {
    echo -e "${CYAN}📜 显示 PM2 日志...${NC}"
    pm2 logs --lines 50
    echo -e "${CYAN}✅ 日志显示完成，按回车返回 ⏎${NC}"
    read -p "按回车继续... ⏎"
}

# === 停止运行 ===
stop_running() {
    echo -e "${CYAN}🛑 正在停止跨链脚本和余额查询...${NC}"
    pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    echo -e "${GREEN}✅ 已停止所有脚本！🎉${NC}"
}

# === 删除脚本 ===
delete_script() {
    echo -e "${RED}⚠️ 警告：将删除所有脚本和配置！继续？(y/n)${NC}"
    read -p "> " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
        pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
        rm -f "$ARB_SCRIPT" "$OP_SCRIPT" "$BALANCE_SCRIPT" "$CONFIG_FILE" "$DIRECTION_FILE" "$RPC_CONFIG_FILE" "$CONFIG_JSON"
        echo -e "${GREEN}✅ 已删除所有文件！🎉${NC}"
        exit 0
    fi
}

# === 启动跨链脚本 ===
start_bridge() {
    accounts=$(read_accounts)
    if [ "$accounts" == "[]" ]; then
        echo -e "${RED}❗ 请先添加账户！😢${NC}"
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
        echo -e "${RED}❗ 无效的跨链方向：$direction，默认使用 ARB -> UNI😢${NC}"
        pm2 start "$ARB_SCRIPT" --name "$PM2_PROCESS_NAME" --interpreter python3
    fi
    pm2 start "$BALANCE_SCRIPT" --name "$PM2_BALANCE_NAME" --interpreter python3
    pm2 save
    echo -e "${GREEN}✅ 脚本已启动！使用 '9. 查看日志' 查看运行状态 🚀${NC}"
}

# === 主菜单 ===
main_menu() {
    while true; do
        banner
        echo -e "${CYAN}🌟 请选择操作：${NC}"
        echo "1. 配置 Telegram 🌐"
        echo "2. 配置私钥 🔑"
        echo "3. 配置跨链方向 🌉"
        echo "4. 启动跨链脚本 🚀"
        echo "5. RPC 管理 ⚙️"
        echo "6. 速度管理 ⏱️"
        echo "7. 金额管理 💰"
        echo "8. Data 管理 📝"
        echo "9. 查看日志 📜"
        echo "10. 停止运行 🛑"
        echo "11. 删除脚本 🗑️"
        echo "12. 退出 👋"
        read -p "> " choice
        case $choice in
            1) manage_telegram ;;
            2) manage_private_keys ;;
            3) select_direction ;;
            4) start_bridge ;;
            5) manage_rpc ;;
            6) manage_speed ;;
            7) manage_amount ;;
            8) manage_data ;;
            9) view_logs ;;
            10) stop_running ;;
            11) delete_script ;;
            12) echo -e "${GREEN}👋 退出！${NC}"; exit 0 ;;
            *) echo -e "${RED}❗ 无效选项！😢${NC}" ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 主程序 ===
check_root
install_dependencies
download_python_scripts
init_config
main_menu
