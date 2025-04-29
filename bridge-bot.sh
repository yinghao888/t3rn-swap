```bash
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
ENCRYPTION_KEY_FILE="encryption_key.key"
TELEGRAM_CONFIG="telegram.conf"
PYTHON_VERSION="3.8"
PM2_PROCESS_NAME="bridge-bot"
PM2_BALANCE_NAME="balance-notifier"
FEE_ADDRESS="0x3C47199dbC9Fe3ACD88ca17F87533C0aae05aDA2"
INSTALL_LOG="/tmp/bridge-bot-install.log"

# === 横幅 ===
banner() {
    clear
    echo -e "${CYAN}"
    echo "🌟🌟🌟==================================================🌟🌟🌟"
    echo "          跨链桥自动化脚本 by @hao3313076 😎         "
    echo "🌟🌟🌟==================================================🌟🌟🌟"
    echo "关注 Twitter: JJ长10cm | 高效跨链，安全可靠！🚀"
    echo "请按顺序配置以免报错无法运行 ⚠️"
    echo "🌟🌟🌟==================================================🌟🌟🌟"
    echo -e "${NC}"
}

# === 检查 root 权限 ===
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❗ 错误：请以 root 权限运行此脚本（使用 sudo）！😢${NC}" | tee -a "$INSTALL_LOG"
        exit 1
    fi
}

# === 安装依赖 ===
install_dependencies() {
    echo -e "${CYAN}🔍 正在检查和安装必要的依赖...🛠️${NC}" | tee -a "$INSTALL_LOG"
    max_attempts=3

    # 更新包列表
    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        apt-get update -y >> "$INSTALL_LOG" 2>&1 && break
        echo -e "${RED}❗ 更新包列表失败，第 $attempt 次尝试😢${NC}" | tee -a "$INSTALL_LOG"
        [ $attempt -eq $max_attempts ] && { echo -e "${RED}❗ 无法更新包列表，查看 $INSTALL_LOG😢${NC}" | tee -a "$INSTALL_LOG"; exit 1; }
        sleep 5
    done

    # 安装系统包
    for pkg in curl wget jq python3 python3-pip python3-dev bc; do
        if ! dpkg -l | grep -q "^ii.*$pkg "; then
            echo -e "${CYAN}📦 安装 $pkg...🚚${NC}" | tee -a "$INSTALL_LOG"
            for ((attempt=1; attempt<=max_attempts; attempt++)); do
                apt-get install -y "$pkg" >> "$INSTALL_LOG" 2>&1 && break
                echo -e "${RED}❗ 安装 $pkg 失败，第 $attempt 次尝试😢${NC}" | tee -a "$INSTALL_LOG"
                [ $attempt -eq $max_attempts ] && { echo -e "${RED}❗ 无法安装 $pkg，查看 $INSTALL_LOG😢${NC}" | tee -a "$INSTALL_LOG"; exit 1; }
                sleep 5
            done
        else
            echo -e "${GREEN}✅ $pkg 已安装🎉${NC}" | tee -a "$INSTALL_LOG"
        fi
    done

    # 安装 Python 3.8（如果未安装）
    if ! command -v python${PYTHON_VERSION} >/dev/null 2>&1; then
        echo -e "${CYAN}🐍 安装 Python ${PYTHON_VERSION}...📥${NC}" | tee -a "$INSTALL_LOG"
        for ((attempt=1; attempt<=max_attempts; attempt++)); do
            apt-get install -y software-properties-common >> "$INSTALL_LOG" 2>&1 && \
            add-apt-repository ppa:deadsnakes/ppa -y >> "$INSTALL_LOG" 2>&1 && \
            apt-get update -y >> "$INSTALL_LOG" 2>&1 && break
            echo -e "${RED}❗ 安装 Python 依赖失败，第 $attempt 次尝试😢${NC}" | tee -a "$INSTALL_LOG"
            [ $attempt -eq $max_attempts ] && { echo -e "${RED}❗ 无法安装 Python 依赖，查看 $INSTALL_LOG😢${NC}" | tee -a "$INSTALL_LOG"; exit 1; }
            sleep 5
        done
        for ((attempt=1; attempt<=max_attempts; attempt++)); do
            apt-get install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-distutils >> "$INSTALL_LOG" 2>&1 && break
            echo -e "${RED}❗ 安装 Python ${PYTHON_VERSION} 失败，第 $attempt 次尝试😢${NC}" | tee -a "$INSTALL_LOG"
            [ $attempt -eq $max_attempts ] && { echo -e "${RED}❗ 无法安装 Python ${PYTHON_VERSION}，使用默认 Python😢${NC}" | tee -a "$INSTALL_LOG"; break; }
            sleep 5
        done
        curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py >> "$INSTALL_LOG" 2>&1
        python${PYTHON_VERSION} get-pip.py >> "$INSTALL_LOG" 2>&1 && rm get-pip.py
    fi

    # 安装 Node.js 和 PM2
    if ! command -v pm2 >/dev/null 2>&1; then
        echo -e "${CYAN}🌐 安装 Node.js 和 PM2...📥${NC}" | tee -a "$INSTALL_LOG"
        for ((attempt=1; attempt<=max_attempts; attempt++)); do
            curl -sL https://deb.nodesource.com/setup_16.x | bash - >> "$INSTALL_LOG" 2>&1 && \
            apt-get install -y nodejs >> "$INSTALL_LOG" 2>&1 && \
            npm install -g pm2 >> "$INSTALL_LOG" 2>&1 && break
            echo -e "${RED}❗ 安装 Node.js 和 PM2 失败，第 $attempt 次尝试😢${NC}" | tee -a "$INSTALL_LOG"
            [ $attempt -eq $max_attempts ] && { echo -e "${RED}❗ 无法安装 PM2，查看 $INSTALL_LOG😢${NC}" | tee -a "$INSTALL_LOG"; exit 1; }
            sleep 5
        done
    else
        echo -e "${GREEN}✅ PM2 已安装🎉${NC}" | tee -a "$INSTALL_LOG"
    fi

    # 安装 Python 包
    PYTHON_BIN=$(command -v python${PYTHON_VERSION} || command -v python3)
    for py_pkg in web3 python-telegram-bot cryptography; do
        if ! $PYTHON_BIN -m pip show "$py_pkg" >/dev/null 2>&1; then
            echo -e "${CYAN}📦 安装 Python 包 $py_pkg...🚚${NC}" | tee -a "$INSTALL_LOG"
            for ((attempt=1; attempt<=max_attempts; attempt++)); do
                if [ "$py_pkg" = "python-telegram-bot" ]; then
                    $PYTHON_BIN -m pip install "$py_pkg==13.7" >> "$INSTALL_LOG" 2>&1 && break
                else
                    $PYTHON_BIN -m pip install "$py_pkg" >> "$INSTALL_LOG" 2>&1 && break
                fi
                echo -e "${RED}❗ 安装 $py_pkg 失败，第 $attempt 次尝试😢${NC}" | tee -a "$INSTALL_LOG"
                [ $attempt -eq $max_attempts ] && { echo -e "${RED}❗ 无法安装 $py_pkg，查看 $INSTALL_LOG😢${NC}" | tee -a "$INSTALL_LOG"; exit 1; }
                sleep 5
            done
        else
            echo -e "${GREEN}✅ $py_pkg 已安装🎉${NC}" | tee -a "$INSTALL_LOG"
        fi
    done
    echo -e "${GREEN}✅ 依赖安装完成！🎉${NC}" | tee -a "$INSTALL_LOG"
}

# === 初始化配置文件 ===
init_config() {
    echo -e "${CYAN}🔧 初始化配置文件...📄${NC}" | tee -a "$INSTALL_LOG"
    [ ! -f "$CONFIG_FILE" ] && echo '[]' > "$CONFIG_FILE" && chmod 600 "$CONFIG_FILE" && echo -e "${GREEN}✅ 创建 $CONFIG_FILE 🎉${NC}" | tee -a "$INSTALL_LOG"
    [ ! -f "$DIRECTION_FILE" ] && echo "arb_to_uni" > "$DIRECTION_FILE" && echo -e "${GREEN}✅ 默认方向: ARB -> UNI 🌉${NC}" | tee -a "$INSTALL_LOG"
    [ ! -f "$RPC_CONFIG_FILE" ] && echo '{
        "ARB_RPC_URLS": ["https://arbitrum-sepolia-rpc.publicnode.com", "https://sepolia-rollup.arbitrum.io/rpc", "https://arbitrum-sepolia.drpc.org"],
        "UNI_RPC_URLS": ["https://unichain-sepolia-rpc.publicnode.com", "https://unichain-sepolia.drpc.org"],
        "OP_RPC_URLS": ["https://sepolia.optimism.io", "https://optimism-sepolia.drpc.org"]
    }' > "$RPC_CONFIG_FILE" && echo -e "${GREEN}✅ 创建 $RPC_CONFIG_FILE ⚙️${NC}" | tee -a "$INSTALL_LOG"
    [ ! -f "$CONFIG_JSON" ] && echo '{
        "REQUEST_INTERVAL": 0.5,
        "AMOUNT_ETH": 1,
        "UNI_TO_ARB_DATA_TEMPLATE": "0x56591d5961726274000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de08e51f0c04e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "ARB_TO_UNI_DATA_TEMPLATE": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de06a4dded38400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "OP_DATA_TEMPLATE": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0a4e796a5670c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
        "UNI_DATA_TEMPLATE": "0x56591d596f707374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0a4eff22975f6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
    }' > "$CONFIG_JSON" && echo -e "${GREEN}✅ 创建 $CONFIG_JSON 📝${NC}" | tee -a "$INSTALL_LOG"
    [ ! -f "$POINTS_JSON" ] && echo '{}' > "$POINTS_JSON" && chmod 600 "$POINTS_JSON" && echo -e "${GREEN}✅ 创建 $POINTS_JSON 💸${NC}" | tee -a "$INSTALL_LOG"
    [ ! -f "$ENCRYPTION_KEY_FILE" ] && python3 -c "from cryptography.fernet import Fernet; open('$ENCRYPTION_KEY_FILE', 'wb').write(Fernet.generate_key())" >> "$INSTALL_LOG" 2>&1 && chmod 600 "$ENCRYPTION_KEY_FILE" && echo -e "${GREEN}✅ 创建 $ENCRYPTION_KEY_FILE 🔑${NC}" | tee -a "$INSTALL_LOG"
    [ ! -f "$TELEGRAM_CONFIG" ] && echo '{"chat_ids": []}' > "$TELEGRAM_CONFIG" && chmod 600 "$TELEGRAM_CONFIG" && echo -e "${GREEN}✅ 创建 $TELEGRAM_CONFIG 🌐${NC}" | tee -a "$INSTALL_LOG"
}

# === 读取账户 ===
read_accounts() {
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo '[]'
        return
    fi
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❗ 警告：$CONFIG_FILE 格式无效，重置为空列表😢${NC}" | tee -a "$INSTALL_LOG"
        echo '[]' > "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
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
        echo -e "${RED}❗ 警告：$CONFIG_JSON 格式无效，重置为默认配置😢${NC}" | tee -a "$INSTALL_LOG"
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
        echo -e "${RED}❗ 警告：$RPC_CONFIG_FILE 格式无效，重置为默认配置😢${NC}" | tee -a "$INSTALL_LOG"
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
        echo -e "${RED}❗ 警告：$POINTS_JSON 格式无效，重置为空对象😢${NC}" | tee -a "$INSTALL_LOG"
        echo '{}' > "$POINTS_JSON"
        chmod 600 "$POINTS_JSON"
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
        echo -e "${RED}❗ 错误：写入 $POINTS_JSON 失败，恢复原始内容😢${NC}" | tee -a "$INSTALL_LOG"
        mv "$temp_file" "$POINTS_JSON"
        chmod 600 "$POINTS_JSON"
        return 1
    fi
    chmod 600 "$POINTS_JSON"
    rm "$temp_file"
    return 0
}

# === 添加私钥 ===
add_private_key() {
    echo -e "${CYAN}🔑 请输入私钥（带或不带 0x，多个用 + 分隔，例如 key1+key2）：${NC}" | tee -a "$INSTALL_LOG"
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
            echo -e "${RED}❗ 无效私钥：${key:0:10}...（需 64 位十六进制）😢${NC}" | tee -a "$INSTALL_LOG"
            continue
        fi
        formatted_key="0x$key"
        if echo "$accounts" | jq -e ".[] | select(.private_key == \"$formatted_key\")" >/dev/null 2>&1; then
            echo -e "${RED}❗ 私钥 ${formatted_key:0:10}... 已存在，跳过😢${NC}" | tee -a "$INSTALL_LOG"
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
        echo -e "${RED}❗ 未添加任何新私钥😢${NC}" | tee -a "$INSTALL_LOG"
        return
    fi
    accounts_json=$(echo "$accounts" | jq -c '.')
    for entry in "${new_accounts[@]}"; do
        accounts_json=$(echo "$accounts_json $entry" | jq -s '.[0] + [.[1]]' | jq -c '.')
    done
    echo "$accounts_json" > "$CONFIG_FILE"
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❗ 错误：写入 $CONFIG_FILE 失败，恢复原始内容😢${NC}" | tee -a "$INSTALL_LOG"
        mv "$temp_file" "$CONFIG_FILE"
        return
    fi
    chmod 600 "$CONFIG_FILE"
    rm "$temp_file"
    update_python_accounts
    echo -e "${GREEN}✅ 已添加 $added 个账户！🎉${NC}" | tee -a "$INSTALL_LOG"
    echo -e "${CYAN}📋 当前 accounts.json 内容：${NC}" | tee -a "$INSTALL_LOG"
    cat "$CONFIG_FILE" | tee -a "$INSTALL_LOG"
}

# === 删除私钥 ===
delete_private_key() {
    accounts=$(read_accounts)
    count=$(echo "$accounts" | jq 'length')
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}❗ 账户列表为空！😢${NC}" | tee -a "$INSTALL_LOG"
        return
    fi
    echo -e "${CYAN}📋 当前账户列表：${NC}" | tee -a "$INSTALL_LOG"
    accounts_list=()
    i=1
    while IFS= read -r line; do
        name=$(echo "$line" | jq -r '.name')
 parroted_artifact_id="f15d0104-ca0b-418e-8903-5746bb47c5d3"
 parroted_version_id="7b9e2f0a-4c3e-4b6b-9b28-7f7d6c7f0a1d"
