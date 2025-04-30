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
TELEGRAM_BOT_TOKEN="8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38"
TELEGRAM_CHAT_ID=""
POINTS_HASH_FILE="points.hash"
VENV_PATH="$HOME/venv"

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
    for pkg in curl wget jq python3 python3-pip python3-dev python3-venv bc coreutils pipx; do
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

    # 创建虚拟环境并安装库
    if [ ! -d "$VENV_PATH" ]; then
        echo -e "${CYAN}📦 创建虚拟环境...🚚${NC}"
        python3 -m venv "$VENV_PATH" || { echo -e "${RED}❗ 无法创建虚拟环境，请检查 Python 环境和权限😢${NC}"; exit 1; }
    fi

    # 检查虚拟环境是否创建成功
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        echo -e "${RED}❗ 虚拟环境激活文件 $VENV_PATH/bin/activate 不存在，创建失败😢${NC}"
        exit 1
    fi

    # 激活虚拟环境
    source "$VENV_PATH/bin/activate" || { echo -e "${RED}❗ 无法激活虚拟环境 $VENV_PATH/bin/activate😢${NC}"; exit 1; }

    # 安装 Python 依赖
    for py_pkg in web3 cryptography; do
        if ! "$VENV_PATH/bin/pip" show "$py_pkg" >/dev/null 2>&1; then
            echo -e "${CYAN}📦 安装 $py_pkg（虚拟环境）...🚚${NC}"
            "$VENV_PATH/bin/pip" install "$py_pkg" || { echo -e "${RED}❗ 无法安装 $py_pkg😢${NC}"; deactivate; exit 1; }
        else
            echo -e "${GREEN}✅ $py_pkg 已安装（虚拟环境）🎉${NC}"
        fi
    done
    deactivate

    # 使用 pipx 安装应用
    if ! pipx list | grep -q "python-telegram-bot"; then
        echo -e "${CYAN}📦 安装 python-telegram-bot...🚚${NC}"
        pipx install python-telegram-bot || { echo -e "${RED}❗ 无法安装 python-telegram-bot😢${NC}"; exit 1; }
    else
        echo -e "${GREEN}✅ python-telegram-bot 已安装🎉${NC}"
    fi

    if ! command -v sha256sum >/dev/null 2>&1; then
        echo -e "${RED}❗ sha256sum 命令不可用，请确保 coreutils 已安装😢${NC}"
        exit 1
    fi
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
        "ARB_RPC_URLS": ["https://sepolia-rollup.arbitrum.io/rpc", "https://endpoints.omniatech.io/v1/arbitrum/sepolia/public"],
        "UNI_RPC_URLS": ["https://sepolia.unichain.org", "https://unichain-sepolia-rpc.publicnode.com"],
        "OP_RPC_URLS": ["https://sepolia.optimism.io", "https://endpoints.omniatech.io/v1/op/sepolia/public", "https://rpc.therpc.io/optimism-sepolia"]
    }' > "$RPC_CONFIG_FILE" && echo -e "${GREEN}✅ 创建 $RPC_CONFIG_FILE ⚙️${NC}"
    [ ! -f "$CONFIG_JSON" ] && echo '{
        "REQUEST_INTERVAL": 0.5,
        "AMOUNT_ETH": 1,
        "UNI_TO_ARB_DATA_TEMPLATE": "0x56591d5961726274000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de08e51f0c04e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "ARB_TO_UNI_DATA_TEMPLATE": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de06a4dded38400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "OP_DATA_TEMPLATE": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0a4e796a5670c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "UNI_DATA_TEMPLATE": "0x56591d596f707374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0a4eff22975f6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
    }' > "$CONFIG_JSON" && echo -e "${GREEN}✅ 创建 $CONFIG_JSON 📝${NC}"
    if [ ! -f "$POINTS_JSON" ]; then
        echo '{}' > "$POINTS_JSON" && echo -e "${GREEN}✅ 创建 $POINTS_JSON 💸${NC}"
        sha256sum "$POINTS_JSON" > "$POINTS_HASH_FILE" 2>/dev/null || {
            echo -e "${RED}❗ 无法创建 $POINTS_HASH_FILE，请检查写入权限😢${NC}"
            exit 1
        }
        echo -e "${GREEN}✅ 创建 $POINTS_HASH_FILE 🎉${NC}"
    fi
}

# === 验证点数文件完整性 ===
validate_points_file() {
    if [ ! -f "$POINTS_JSON" ] || [ ! -f "$POINTS_HASH_FILE" ]; then
        echo -e "${RED}❗ 点数文件或哈希文件缺失！尝试重新创建...😢${NC}"
        echo '{}' > "$POINTS_JSON"
        sha256sum "$POINTS_JSON" > "$POINTS_HASH_FILE" 2>/dev/null || {
            echo -e "${RED}❗ 无法创建 $POINTS_HASH_FILE，请检查写入权限😢${NC}"
            exit 1
        }
        echo -e "${GREEN}✅ 点数文件已重新创建🎉${NC}"
    fi
    current_hash=$(sha256sum "$POINTS_JSON" | awk '{print $1}')
    stored_hash=$(awk '{print $1}' "$POINTS_HASH_FILE")
    if [ "$current_hash" != "$stored_hash" ]; then
        echo -e "${RED}❗ 点数文件被篡改！😢${NC}"
        send_telegram_notification "点数文件被篡改，脚本退出！"
        exit 1
    fi
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
            "ARB_RPC_URLS": ["https://sepolia-rollup.arbitrum.io/rpc", "https://endpoints.omniatech.io/v1/arbitrum/sepolia/public"],
            "UNI_RPC_URLS": ["https://sepolia.unichain.org", "https://unichain-sepolia-rpc.publicnode.com"],
            "OP_RPC_URLS": ["https://sepolia.optimism.io", "https://endpoints.omniatech.io/v1/op/sepolia/public", "https://rpc.therpc.io/optimism-sepolia"]
        }' > "$RPC_CONFIG_FILE"
        echo '{}'
        return
    fi
    cat "$RPC_CONFIG_FILE"
}

# === 读取点数状态 ===
read_points() {
    validate_points_file
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
        rm -f "$temp_file"
        return 1
    fi
    sha256sum "$POINTS_JSON" > "$POINTS_HASH_FILE" 2>/dev/null || {
        echo -e "${RED}❗ 无法更新 $POINTS_HASH_FILE，请检查写入权限😢${NC}"
        mv "$temp_file" "$POINTS_JSON"
        rm -f "$temp_file"
        return 1
    }
    rm -f "$temp_file"
    return 0
}

# === 检查账户点数 ===
check_account_points() {
    local address="$1"
    local required_points="$2"
    points_json=$(read_points)
    current_points=$(echo "$points_json" | jq -r ".\"$address\" // 0")
    if [ "$current_points" -lt "$required_points" ]; then
        echo -e "${RED}❗ 账户 $address 点数不足（当前：$current_points，需：$required_points）😢${NC}"
        send_telegram_notification "账户 $address 点数不足（当前：$current_points，需：$required_points），请充值！"
        return 1
    fi
    return 0
}

# === 发送 Telegram 通知 ===
send_telegram_notification() {
    local message="$1"
    if [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo -e "${RED}❗ Telegram Chat ID 未配置，请在菜单中设置！😢${NC}"
        return 1
    fi
    local encoded_message=$(echo -n "$message" | jq -sRr @uri)
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$encoded_message" >/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Telegram 通知已发送🎉${NC}"
    else
        echo -e "${RED}❗ Telegram 通知发送失败😢${NC}"
    fi
}

# === 查询账户余额 ===
get_account_balance() {
    local address="$1"
    local chain="$2"
    local balance_wei=0
    case "$chain" in
        "OP")
            rpc_urls=$(jq -r '.OP_RPC_URLS[]' "$RPC_CONFIG_FILE")
            ;;
        "ARB")
            rpc_urls=$(jq -r '.ARB_RPC_URLS[]' "$RPC_CONFIG_FILE")
            ;;
        "UNI")
            rpc_urls=$(jq -r '.UNI_RPC_URLS[]' "$RPC_CONFIG_FILE")
            ;;
        *)
            echo "0"
            return 1
            ;;
    esac
    for url in $rpc_urls; do
        balance_wei=$("$VENV_PATH/bin/python3" -c "from web3 import Web3; w3 = Web3(Web3.HTTPProvider('$url')); print(w3.eth.get_balance('$address'))" 2>/dev/null)
        if [ -n "$balance_wei" ]; then
            break
        fi
    done
    if [ -z "$balance_wei" ]; then
        echo "0"
        return 1
    fi
    balance_eth=$("$VENV_PATH/bin/python3" -c "print('{:.6f}'.format($balance_wei / 10**18))" 2>/dev/null)
    echo "$balance_eth"
}

# === 添加私钥 ===
add_private_key() {
    validate_points_file
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
        key_media: key=$(echo "$key" | tr -d '[:space:]')
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
        address=$("$VENV_PATH/bin/python3" -c "from web3 import Web3; print(Web3(Web3.HTTPProvider('https://sepolia.unichain.org')).eth.account.from_key('$formatted_key').address)" 2>/dev/null)
        if [ -z "$address" ]; then
            echo -e "${RED}❗ 无法计算私钥 ${formatted_key:0:10}... 的地址，跳过😢${NC}"
            continue
        fi
        count=$((count + 1))
        name="Account$count"
        new_entry="{\"name\": \"$name\", \"private_key\": \"$formatted_key\", \"address\": \"$address\"}"
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
        rm "$temp_file"
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
    validate_points_file
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
        address=$(echo "$line" | jq -r '.address')
        if [ -z "$address" ]; then
            address=$("$VENV_PATH/bin/python3" -c "from web3 import Web3; print(Web3(Web3.HTTPProvider('https://sepolia.unichain.org')).eth.account.from_key('$key').address)" 2>/dev/null)
        fi
        if [ -n "$name" ] && [ -n "$key" ] && [ -n "$address" ]; then
            op_balance=$(get_account_balance "$address" "OP")
            arb_balance=$(get_account_balance "$address" "ARB")
            uni_balance=$(get_account_balance "$address" "UNI")
            accounts_list+=("$line")
            echo "$i. $name (${address:0:10}...) OP: $op_balance ETH, ARB: $arb_balance ETH, UNI: $uni_balance ETH"
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
        rm "$temp_file"
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
    validate_points_file
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
    validate_points_file
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
        address=$(echo "$line" | jq -r '.address')
        if [ -z "$address" ]; then
            address=$("$VENV_PATH/bin/python3" -c "from web3 import Web3; print(Web3(Web3.HTTPProvider('https://sepolia.unichain.org')).eth.account.from_key('$key').address)" 2>/dev/null)
        fi
        if [ -n "$name" ] && [ -n "$key" ] && [ -n "$address" ]; then
            op_balance=$(get_account_balance "$address" "OP")
            arb_balance=$(get_account_balance "$address" "ARB")
            uni_balance=$(get_account_balance "$address" "UNI")
            echo "$i. $name (${address:0:10}...${address: -4}) OP: $op_balance ETH, ARB: $arb_balance ETH, UNI: $uni_balance ETH"
            i=$((i + 1))
        fi
    done < <(echo "$accounts" | jq -c '.[]')
    if [ $i -eq 1 ]; then
        echo -e "${RED}❗ 账户列表为空！😢${NC}"
    fi
}

# === 管理 Telegram IDs ===
manage_telegram() {
    validate_points_file
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
            1)
                echo -e "${CYAN}🌐 请输入 Telegram 用户 ID（纯数字，例如 5963704377）：${NC}"
                echo -e "${CYAN}📢 请先关注 @GetMyIDBot 获取您的 Telegram ID！😎${NC}"
                read -p "> " chat_id
                if [[ ! "$chat_id" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}❗ 无效 ID，必须为纯数字！😢${NC}"
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
            4)
                break
                ;;
            *)
                echo -e "${RED}❗ 无效选项！😢${NC}"
                ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 管理私钥 ===
manage_private_keys() {
    validate_points_file
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
    validate_points_file
    echo -e "${CYAN}💸 请输入充值金额（整数 ETH，最小 1 ETH，例如 1）：${NC}"
    echo -e "${CYAN}📋 兑换规则：1 ETH = 50,000 点${NC}"
    echo -e "${CYAN}📋 折扣信息（基于点数）：${NC}"
    echo "  - 100,000 点（2 ETH）：8.5折（0.85）"
    echo "  - 500,000 点（10 ETH）：7折（0.7）"
    echo "  - 1,000,000 点（20 ETH）：6折（0.6）"
    echo "  - 5,000,000 点（100 ETH）：5折（0.5）"
    read -p "> " amount_eth
    if [[ ! "$amount_eth" =~ ^[0-9]+$ ]] || [ "$amount_eth" -lt 1 ]; then
        echo -e "${RED}❗ 无效输入，必须为正整数且至少 1 ETH！😢${NC}"
        return
    fi
    points=$((amount_eth * 50000))
    discount=1
    if [ "$points" -ge 5000000 ]; then
        discount=0.5
    elif [ "$points" -ge 1000000 ]; then
        discount=0.6
    elif [ "$points" -ge 500000 ]; then
        discount=0.7
    elif [ "$points" -ge 100000 ]; then
        discount=0.85
    fi
    discounted_eth=$("$VENV_PATH/bin/python3" -c "print('{:.6f}'.format($amount_eth * $discount))")
    echo -e "${CYAN}💸 将获得 $points 点，需支付 $discounted_eth ETH（折扣：${discount}）${NC}"
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
        address=$(echo "$line" | jq -r '.address')
        if [ -z "$address" ]; then
            address=$("$VENV_PATH/bin/python3" -c "from web3 import Web3; print(Web3(Web3.HTTPProvider('https://sepolia.unichain.org')).eth.account.from_key('$key').address)" 2>/dev/null)
            if [ -z "$address" ]; then
                echo -e "${RED}❗ 无法计算账户 $name 的地址，跳过😢${NC}"
                continue
            fi
            temp_file=$(mktemp)
            echo "$accounts" > "$temp_file"
            accounts_json=$(echo "$accounts" | jq -c ".[] | select(.private_key == \"$key\") |= . + {\"address\": \"$address\"}")
            echo "$accounts_json" > "$CONFIG_FILE"
            if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
                echo -e "${RED}❗ 错误：写入 $CONFIG_FILE 失败，恢复原始内容😢${NC}"
                mv "$temp_file" "$CONFIG_FILE"
                rm "$temp_file"
                continue
            fi
            rm "$temp_file"
        fi
        if [ -n "$name" ] && [ -n "$key" ] && [ -n "$address" ]; then
            op_balance=$(get_account_balance "$address" "OP")
            arb_balance=$(get_account_balance "$address" "ARB")
            uni_balance=$(get_account_balance "$address" "UNI")
            accounts_list+=("{\"name\": \"$name\", \"private_key\": \"$key\", \"address\": \"$address\"}")
            echo "$i. $name (${address:0:10}...) OP: $op_balance ETH, ARB: $arb_balance ETH, UNI: $uni_balance ETH"
            i=$((i + 1))
        fi
    done < <(echo "$accounts" | jq -c '.[]')
    if [ ${#accounts_list[@]} -eq 0 ]; then
        echo -e "${RED}❗ 账户列表为空！😢${NC}"
        return
    fi
    echo -e "${CYAN}🔍 请选择充值账户编号：${NC}"
    read -p "> " index
    if [ -z "$index" ] || [ "$index" -le 0 ] || [ "$index" -gt "${#accounts_list[@]}" ]; then
        echo -e "${RED}❗ 无效编号！😢${NC}"
        return
    fi
    account=$(echo "${accounts_list[$((index-1))]}" | jq -r '.private_key')
    address=$(echo "${accounts_list[$((index-1))]}" | jq -r '.address')
    if [ -z "$address" ] || [ "$address" == "null" ]; then
        address=$("$VENV_PATH/bin/python3" -c "from web3 import Web3; print(Web3(Web3.HTTPProvider('https://sepolia.unichain.org')).eth.account.from_key('$account').address)" 2>/dev/null)
        if [ -z "$address" ]; then
            echo -e "${RED}❗ 无法计算账户地址！😢${NC}"
            return
        fi
    fi
    chains=("ARB" "UNI" "OP")
    amount_wei=$("$VENV_PATH/bin/python3" -c "print(int($discounted_eth * 10**18))")
    gas_limit=21000
    max_attempts=3
    for c in "${chains[@]}"; do
        case "$c" in
            "ARB")
                rpc_urls=$(jq -r '.ARB_RPC_URLS[]' "$RPC_CONFIG_FILE")
                chain_id=421614
                ;;
            "UNI")
                rpc_urls=$(jq -r '.UNI_RPC_URLS[]' "$RPC_CONFIG_FILE")
                chain_id=1301
                ;;
            "OP")
                rpc_urls=$(jq -r '.OP_RPC_URLS[]' "$RPC_CONFIG_FILE")
                chain_id=11155420
                ;;
        esac
        for url in $rpc_urls; do
            echo -e "${CYAN}🔍 检查 $c 链余额（使用 RPC: $url）...${NC}"
            temp_script=$(mktemp)
            cat << EOF > "$temp_script"
import sys
from web3 import Web3
rpc_url = "$url"
address = "$address"
amount_eth = $discounted_eth
gas_limit = $gas_limit
try:
    w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={'timeout': 10}))
    if not w3.is_connected():
        print('RPC connection failed', file=sys.stderr)
        sys.exit(1)
    balance_eth = w3.from_wei(w3.eth.get_balance(address), 'ether')
    gas_price = w3.from_wei(w3.eth.gas_price, 'ether')
    total_cost = amount_eth + (gas_price * gas_limit)
    if balance_eth < total_cost:
        print(f'Insufficient balance: {balance_eth} ETH < {total_cost} ETH', file=sys.stderr)
        sys.exit(1)
    print('Sufficient balance')
except Exception as e:
    print(f'Check failed: {str(e)}', file=sys.stderr)
    sys.exit(1)
EOF
            tx_output=$("$VENV_PATH/bin/python3" "$temp_script" 2>&1)
            rm -f "$temp_script"
            if echo "$tx_output" | grep -q "Sufficient balance"; then
                echo -e "${CYAN}💸 将从 $c 链转账 $discounted_eth ETH 到 $FEE_ADDRESS（使用 RPC: $url）...${NC}"
                for ((attempt=1; attempt<=max_attempts; attempt++)); do
                    temp_script=$(mktemp)
                    cat << EOF > "$temp_script"
import sys
from web3 import Web3
rpc_url = "$url"
account = "$account"
address = "$address"
fee_address = "$FEE_ADDRESS"
amount_wei = $amount_wei
chain_id = $chain_id
gas_limit = $gas_limit
try:
    w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={'timeout': 10}))
    if not w3.is_connected():
        print('RPC connection failed', file=sys.stderr)
        sys.exit(1)
    account = w3.eth.account.from_key(account)
    nonce = w3.eth.get_transaction_count(address)
    gas_price = w3.eth.gas_price
    tx = {
        'to': fee_address,
        'value': int(amount_wei),
        'nonce': nonce,
        'gas': gas_limit,
        'gasPrice': gas_price,
        'chainId': int(chain_id)
    }
    signed_tx = w3.eth.account.sign_transaction(tx, account.key)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction).hex()
    print(tx_hash)
except Exception as e:
    print(f'Transaction failed: {str(e)}', file=sys.stderr)
    sys.exit(1)
EOF
                    tx_output=$("$VENV_PATH/bin/python3" "$temp_script" 2>&1)
                    rm -f "$temp_script"
                    tx_hash=$(echo "$tx_output" | grep -v '^Transaction failed' | grep -E '^[0-9a-fA-Fx]+$')
                    error_message=$(echo "$tx_output" | grep '^Transaction failed' || echo "Unknown error")
                    if [ $? -eq 0 ] && [ -n "$tx_hash" ]; then
                        temp_script=$(mktemp)
                        cat << EOF > "$temp_script"
import sys
from web3 import Web3
rpc_url = "$url"
tx_hash = "$tx_hash"
try:
    w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={'timeout': 10}))
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
    print(receipt['status'])
except Exception as e:
    print(f'Waiting for transaction failed: {str(e)}', file=sys.stderr)
    sys.exit(1)
EOF
                        receipt=$("$VENV_PATH/bin/python3" "$temp_script" 2>&1)
                        rm -f "$temp_script"
                        if [ "$receipt" -eq 1 ]; then
                            current_points=$(jq -r ".\"$address\" // 0" "$POINTS_JSON")
                            new_points=$((current_points + points))
                            update_points "$address" "$new_points"
                            if [ $? -eq 0 ]; then
                                echo -e "${GREEN}✅ 充值成功！账户 $address 获得 $points 点数，总点数：$new_points 🎉${NC}"
                                send_telegram_notification "账户 $address 充值成功，获得 $points 点数，总点数：$new_points，交易哈希：$tx_hash"
                                return
                            else
                                echo -e "${RED}❗ 更新点数失败，恢复原始点数😢${NC}"
                                send_telegram_notification "账户 $address 充值失败，点数更新失败！"
                                return
                            fi
                        fi
                    else
                        echo -e "${RED}❗ 转账失败，第 $attempt 次尝试！错误：$error_message😢${NC}"
                    fi
                    if [ $attempt -lt $max_attempts ]; then
                        echo -e "${CYAN}⏳ 等待 10 秒后重试...${NC}"
                        sleep 10
                    fi
                done
                echo -e "${RED}❗ 在 $c 链上转账失败，尝试下一条链...😢${NC}"
            else
                error_message=$(echo "$tx_output" | grep '^Check failed' || echo "Unknown error")
                echo -e "${RED}❗ 在 $c 链上余额不足或检查失败！错误：$error_message😢${NC}"
            fi
        done
    done
    op_balance=$(get_account_balance "$address" "OP")
    arb_balance=$(get_account_balance "$address" "ARB")
    uni_balance=$(get_account_balance "$address" "UNI")
    echo -e "${RED}❗ 所有链上转账失败，请检查网络、余额或 RPC 配置！😢${NC}"
    echo -e "${CYAN}余额：OP: $op_balance ETH, ARB: $arb_balance ETH, UNI: $uni_balance ETH${NC}"
    send_telegram_notification "账户 $address 充值失败，请检查网络、余额或 RPC 配置！余额：OP: $op_balance ETH, ARB: $arb_balance ETH, UNI: $uni_balance ETH"
}

# === 查看当前 RPC ===
view_rpc_config() {
    validate_points_file
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
    validate_points_file
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
    new_config=$(echo "$rpc_config" | jq -c ".${chain_key} += [\"$rpc_url\"]")
    echo "$new_config" > "$RPC_CONFIG_FILE"
    if ! jq -e . "$RPC_CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❗ 错误：写入 $RPC_CONFIG_FILE 失败，恢复原始内容😢${NC}"
        mv "$temp_file" "$RPC_CONFIG_FILE"
        rm "$temp_file"
        return
    fi
    rm "$temp_file"
    update_python_rpc
    echo -e "${GREEN}✅ 已添加 RPC: $rpc_url 到 $chain_key 🎉${NC}"
}

# === 删除 RPC ===
delete_rpc() {
    validate_points_file
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
    count=$(echo "$rpc_config" | jq ".${chain_key} | length")
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}❗ $chain_key RPC 列表为空！😢${NC}"
        return
    fi
    echo -e "${CYAN}📋 当前 $chain_key RPC 列表：${NC}"
    echo "$rpc_config" | jq -r ".${chain_key}[]" | nl -w2 -s '. '
    echo -e "${CYAN}🔍 请输入要删除的 RPC 编号（或 0 取消）：${NC}"
    read -p "> " index
    [ "$index" -eq 0 ] && return
    if [ -z "$index" ] || [ "$index" -le 0 ] || [ "$index" -gt "$count" ]; then
        echo -e "${RED}❗ 无效编号！😢${NC}"
        return
    fi
    temp_file=$(mktemp)
    echo "$rpc_config" > "$temp_file"
    new_config=$(echo "$rpc_config" | jq -c "del(.${chain_key}[$((index-1))])")
    echo "$new_config" > "$RPC_CONFIG_FILE"
    if ! jq -e . "$RPC_CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❗ 错误：写入 $RPC_CONFIG_FILE 失败，恢复原始内容😢${NC}"
        mv "$temp_file" "$RPC_CONFIG_FILE"
        rm "$temp_file"
        return
    fi
    rm "$temp_file"
    update_python_rpc
    echo -e "${GREEN}✅ 已删除 $chain_key 的 RPC！🎉${NC}"
}

# === 更新 Python 脚本 RPC 配置 ===
update_python_rpc() {
    validate_points_file
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
    sed -i "s|^ARB_RPC_URLS = .*|ARB_RPC_URLS = $arb_rpc_str|" "$ARB_SCRIPT"
    sed -i "s|^UNI_RPC_URLS = .*|UNI_RPC_URLS = $uni_rpc_str|" "$ARB_SCRIPT"
    sed -i "s|^OP_RPC_URLS = .*|OP_RPC_URLS = $op_rpc_str|" "$OP_SCRIPT"
    sed -i "s|^UNI_RPC_URLS = .*|UNI_RPC_URLS = $uni_rpc_str|" "$OP_SCRIPT"
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
    validate_points_file
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
    validate_points_file
    config=$(read_config)
    request_interval=$(echo "$config" | jq -r '.REQUEST_INTERVAL')
    echo -e "${CYAN}⏱️ 当前速度配置：${NC}"
    echo "REQUEST_INTERVAL: $request_interval 秒"
}

# === 修改速度 ===
modify_speed() {
    validate_points_file
    echo -e "${CYAN}⏱️ 请输入新的 REQUEST_INTERVAL（正浮点数，单位：秒，例如 0.01）：${NC}"
    read -p "> " request_interval
    if [[ ! "$request_interval" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$(echo "$request_interval <= 0" | bc)" -eq 1 ]; then
        echo -e "${RED}❗ 无效输入，必须为正浮点数！😢${NC}"
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
        rm "$temp_file"
        return
    fi
    rm "$temp_file"
    update_python_config
    echo -e "${GREEN}✅ 已更新 REQUEST_INTERVAL 为 $request_interval 秒！🎉${NC}"
}

# === 速度管理 ===
manage_speed() {
    validate_points_file
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

# === 更新 Python 脚本配置（REQUEST_INTERVAL, AMOUNT_ETH, DATA_TEMPLATE） ===
update_python_config() {
    validate_points_file
    config=$(read_config)
    request_interval=$(echo "$config" | jq -r '.REQUEST_INTERVAL')
    amount_eth=$(echo "$config" | jq -r '.AMOUNT_ETH')
    uni_to_arb_data=$(echo "$config" | jq -r '.UNI_TO_ARB_DATA_TEMPLATE' | sed "s/'/\\'/g")
    arb_to_uni_data=$(echo "$config" | jq -r '.ARB_TO_UNI_DATA_TEMPLATE' | sed "s/'/\\'/g")
    op_data=$(echo "$config" | jq -r '.OP_DATA_TEMPLATE' | sed "s/'/\\'/g")
    uni_data=$(echo "$config" | jq -r '.UNI_DATA_TEMPLATE' | sed "s/'/\\'/g")
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
    sed -i "s|^REQUEST_INTERVAL = .*|REQUEST_INTERVAL = $request_interval|" "$ARB_SCRIPT"
    sed -i "s|^AMOUNT_ETH = .*|AMOUNT_ETH = $amount_eth|" "$ARB_SCRIPT"
    sed -i "s|^UNI_TO_ARB_DATA_TEMPLATE = .*|UNI_TO_ARB_DATA_TEMPLATE = '$uni_to_arb_data'|" "$ARB_SCRIPT"
    sed -i "s|^ARB_TO_UNI_DATA_TEMPLATE = .*|ARB_TO_UNI_DATA_TEMPLATE = '$arb_to_uni_data'|" "$ARB_SCRIPT"
    sed -i "s|^REQUEST_INTERVAL = .*|REQUEST_INTERVAL = $request_interval|" "$OP_SCRIPT"
    sed -i "s|^AMOUNT_ETH = .*|AMOUNT_ETH = $amount_eth|" "$OP_SCRIPT"
    sed -i "s|^OP_DATA_TEMPLATE = .*|OP_DATA_TEMPLATE = '$op_data'|" "$OP_SCRIPT"
    sed -i "s|^UNI_DATA_TEMPLATE = .*|UNI_DATA_TEMPLATE = '$uni_data'|" "$OP_SCRIPT"
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
    validate_points_file
    accounts=$(read_accounts)
    accounts_str=$(echo "$accounts" | jq -r '[.[] | {"private_key": .private_key, "name": .name}]' | jq -r '@json')
    if [ -z "$accounts_str" ] || [ "$accounts_str" == "[]" ]; then
        accounts_str="[]"
        echo -e "${RED}❗ 警告：账户列表为空，将设置 ACCOUNTS 为空😢${NC}"
    fi
    for script in "$ARB_SCRIPT" "$OP_SCRIPT"; do
        if [ ! -f "$script" ]; then
            echo -e "${RED}❗ 错误：$script 不存在😢${NC}"
            return 1
        fi
        if [ ! -w "$script" ]; then
            echo -e "${RED}❗ 错误：$script 不可写，请检查权限😢${NC}"
            return 1
        fi
        temp_file=$(mktemp)
        cp "$script" "$temp_file" || {
            echo -e "${RED}❗ 错误：无法备份 $script😢${NC}"
            rm -f "$temp_file"
            return 1
        }
        if grep -q "^ACCOUNTS = " "$script"; then
            sed "s|^ACCOUNTS = .*|ACCOUNTS = $accounts_str|" "$script" > "$script.tmp" || {
                echo -e "${RED}❗ 错误：更新 $script 失败😢${NC}"
                mv "$temp_file" "$script"
                rm -f "$script.tmp"
                return 1
            }
        else
            echo "ACCOUNTS = $accounts_str" > "$script.tmp"
            cat "$script" >> "$script.tmp" || {
                echo -e "${RED}❗ 错误：追加 $script 失败😢${NC}"
                mv "$temp_file" "$script"
                rm -f "$script.tmp"
                return 1
            }
        fi
        mv "$script.tmp" "$script" || {
            echo -e "${RED}❗ 错误：移动临时文件到 $script 失败😢${NC}"
            mv "$temp_file" "$script"
            return 1
        }
        current_accounts=$(grep "^ACCOUNTS = " "$script" | sed 's/ACCOUNTS = //')
        normalized_accounts_str=$(echo "$accounts_str" | tr -d ' \n')
        normalized_current_accounts=$(echo "$current_accounts" | tr -d ' \n')
        if [ "$normalized_current_accounts" != "$normalized_accounts_str" ]; then
            echo -e "${RED}❗ 错误：验证 $script 更新失败，内容不匹配😢${NC}"
            echo -e "${CYAN}预期内容：$accounts_str${NC}"
            echo -e "${CYAN}实际内容：$current_accounts${NC}"
            mv "$temp_file" "$script"
            rm -f "$temp_file"
            return 1
        fi
        rm -f "$temp_file"
    done
    echo -e "${GREEN}✅ 已更新 $ARB_SCRIPT 和 $OP_SCRIPT 的账户！🎉${NC}"
    echo -e "${CYAN}📋 当前 $ARB_SCRIPT ACCOUNTS 内容：${NC}"
    grep "^ACCOUNTS = " "$ARB_SCRIPT" || echo "ACCOUNTS 未定义"
    echo -e "${CYAN}📋 当前 $OP_SCRIPT ACCOUNTS 内容：${NC}"
    grep "^ACCOUNTS = " "$OP_SCRIPT" || echo "ACCOUNTS 未定义"
}

# === 配置跨链方向 ===
select_direction() {
    validate_points_file
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
    validate_points_file
    echo -e "${CYAN}📜 显示 PM2 日志...${NC}"
    pm2 logs --lines 50
    echo -e "${CYAN}✅ 日志显示完成，按回车返回 ⏎${NC}"
    read -p "按回车继续... ⏎"
}

# === 停止运行 ===
stop_running() {
    validate_points_file
    echo -e "${CYAN}🛑 正在停止跨链脚本和余额查询...${NC}"
    pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    echo -e "${GREEN}✅ 已停止所有脚本！🎉${NC}"
}

# === 删除脚本 ===
delete_script() {
    validate_points_file
    echo -e "${RED}⚠️ 警告：将删除所有脚本和配置！继续？(y/n)${NC}"
    read -p "> " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
        pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
        rm -f "$ARB_SCRIPT" "$OP_SCRIPT" "$BALANCE_SCRIPT" "$CONFIG_FILE" "$DIRECTION_FILE" "$RPC_CONFIG_FILE" "$CONFIG_JSON" "$POINTS_JSON" "$POINTS_HASH_FILE" "$0"
        echo -e "${GREEN}✅ 已删除所有文件！🎉${NC}"
        exit 0
    fi
}

# === 启动跨链脚本 ===
start_bridge() {
    validate_points_file
    accounts=$(read_accounts)
    if [ "$accounts" == "[]" ]; then
        echo -e "${RED}❗ 请先添加账户！😢${NC}"
        return
    fi
    direction=$(cat "$DIRECTION_FILE")
    script=""
    case "$direction" in
        "arb_to_uni") script="$ARB_SCRIPT" ;;
        "op_to_uni") script="$OP_SCRIPT" ;;
        *) echo -e "${RED}❗ 无效方向！😢${NC}"; return ;;
    esac
    pm2 start "$VENV_PATH/bin/python3" --name "$PM2_PROCESS_NAME" -- "$script" --direction "$direction" >/dev/null 2>&1
    echo -e "${GREEN}✅ 跨链脚本已启动！🎉${NC}"
}

# === 启动余额查询 ===
start_balance_notifier() {
    validate_points_file
    pm2 start "$VENV_PATH/bin/python3" --name "$PM2_BALANCE_NAME" -- "$BALANCE_SCRIPT" --telegram_token "$TELEGRAM_BOT_TOKEN" --telegram_chat_id "$TELEGRAM_CHAT_ID" >/dev/null 2>&1
    echo -e "${GREEN}✅ 余额查询脚本已启动！🎉${NC}"
}

# === 主菜单 ===
main_menu() {
    if [ -f telegram.conf ]; then
        TELEGRAM_CHAT_ID=$(cat telegram.conf)
    fi
    check_root
    install_dependencies
    download_python_scripts
    init_config
    while true; do
        banner
        echo -e "${CYAN}🌟🌟 主菜单 🌟🌟${NC}"
        echo "1. 安装依赖和初始化 📦"
        echo "2. 管理 Telegram ID 🌐"
        echo "3. 管理私钥 🔑"
        echo "4. 充值点数 💸"
        echo "5. 管理 RPC ⚙️"
        echo "6. 管理速度 ⏱️"
        echo "7. 配置跨链方向 🌉"
        echo "8. 启动跨链脚本 🚀"
        echo "9. 启动余额查询 📈"
        echo "10. 查看日志 📜"
        echo "11. 停止运行 �']);
        echo "12. 删除脚本和配置 🗑️"
        echo "13. 退出 🔚"
        read -p "> " choice
        case $choice in
            1)
                install_dependencies
                download_python_scripts
                init_config
                ;;
            2) manage_telegram ;;
            3) manage_private_keys ;;
            4) recharge_points ;;
            5) manage_rpc ;;
            6) manage_speed ;;
            7) select_direction ;;
            8) start_bridge ;;
            9) start_balance_notifier ;;
            10) view_logs ;;
            11) stop_running ;;
            12) delete_script ;;
            13) exit 0 ;;
            *) echo -e "${RED}❗ 无效选项！😢${NC}" ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 启动主菜单 ===
main_menu
