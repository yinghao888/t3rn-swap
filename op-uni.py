from web3 import Web3
import time
from typing import List, Dict
import logging
from concurrent.futures import ThreadPoolExecutor
import os
import json
import requests

# === ANSI 颜色代码 ===
LIGHT_BLUE = "\033[96m"
LIGHT_RED = "\033[95m"
RESET = "\033[0m"

# === 账户配置（由脚本动态更新）===
ACCOUNTS = []

# === 配置日志 ===
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger()

# === RPC 配置（由脚本动态更新）===
OP_RPC = ""
UNI_RPC = ""

# === 合约地址 ===
OP_CONTRACT_ADDRESS = "0xb6Def636914Ae60173d9007E732684a9eEDEF26E"
ARB_CONTRACT_ADDRESS = "0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9"

# === 默认配置 ===
MIN_INTERVAL = 60  # 最小间隔时间（秒）
MAX_INTERVAL = 120  # 最大间隔时间（秒）
AMOUNT_ETH = 0.0001  # 每次跨链金额
GAS_LIMIT_OP = 250000
GAS_LIMIT_UNI = 400000
MIN_GAS_PRICE = Web3.to_wei(0.1, 'gwei')

# === 全局计数器 ===
success_count = 0
total_success_count = 0
start_time = time.time()

def load_config():
    """加载配置文件"""
    global AMOUNT_ETH, MIN_INTERVAL, MAX_INTERVAL
    try:
        with open("config.json", "r") as f:
            config = json.load(f)
            AMOUNT_ETH = config.get("AMOUNT_ETH", AMOUNT_ETH)
            MIN_INTERVAL = config.get("MIN_INTERVAL", MIN_INTERVAL)
            MAX_INTERVAL = config.get("MAX_INTERVAL", MAX_INTERVAL)
    except FileNotFoundError:
        logger.warning("config.json 不存在，使用默认配置")

def get_dynamic_gas_price(w3_instance) -> int:
    """获取动态 Gas Price"""
    try:
        latest_block = w3_instance.eth.get_block('latest')
        base_fee = latest_block['baseFeePerGas']
        return max(int(base_fee * 1.2), MIN_GAS_PRICE)
    except Exception as e:
        logger.warning(f"获取 Gas Price 失败，使用默认值: {e}")
        return MIN_GAS_PRICE

def check_and_deduct_points(address: str, required_points: int = 1) -> bool:
    """检查和扣除点数"""
    try:
        with open("points.json", "r") as f:
            points_data = json.load(f)
        
        # 验证哈希
        with open("points.hash", "r") as f:
            stored_hash = f.read().strip()
        import hashlib
        current_hash = hashlib.sha256(json.dumps(points_data).encode()).hexdigest()
        if current_hash != stored_hash:
            logger.error(f"点数文件被篡改！")
            return False

        current_points = points_data.get(address, 0)
        if current_points < required_points:
            logger.error(f"账户 {address} 点数不足（当前：{current_points}，需：{required_points}）")
            return False

        new_points = current_points - required_points
        points_data[address] = new_points
        
        # 保存新的点数和哈希
        with open("points.json", "w") as f:
            json.dump(points_data, f, indent=2)
        with open("points.hash", "w") as f:
            f.write(hashlib.sha256(json.dumps(points_data).encode()).hexdigest())
            
        logger.info(f"账户 {address} 扣除 {required_points} 点，剩余：{new_points}")
        return True
    except Exception as e:
        logger.error(f"点数检查/更新失败：{e}")
        return False

def send_telegram_notification(message: str):
    """发送 Telegram 通知"""
    try:
        with open("telegram.conf", "r") as f:
            chat_id = f.read().strip()
        if not chat_id:
            return
        
        bot_token = "8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38"
        encoded_message = requests.utils.quote(message)
        url = f"https://api.telegram.org/bot{bot_token}/sendMessage?chat_id={chat_id}&text={encoded_message}"
        requests.post(url)
    except Exception as e:
        logger.error(f"Telegram 通知发送失败：{e}")

def bridge_op_to_uni(account_info: Dict) -> bool:
    """执行 OP -> UNI 跨链"""
    global success_count, total_success_count

    if not check_and_deduct_points(account_info["address"], 1):
        return False

    try:
        w3_op = Web3(Web3.HTTPProvider(OP_RPC))
        if not w3_op.is_connected():
            logger.error("无法连接到 OP RPC")
            return False

        amount_wei = w3_op.to_wei(AMOUNT_ETH, 'ether')
        balance = w3_op.eth.get_balance(account_info["address"])
        gas_price = get_dynamic_gas_price(w3_op)
        total_cost = amount_wei + (gas_price * GAS_LIMIT_OP)

        if balance < total_cost:
            logger.warning(f"{account_info['name']} OP 余额不足")
            send_telegram_notification(f"账户 {account_info['address']} OP 余额不足")
            return False

        nonce = w3_op.eth.get_transaction_count(account_info["address"])
        tx = {
            'from': account_info["address"],
            'to': OP_CONTRACT_ADDRESS,
            'value': amount_wei,
            'nonce': nonce,
            'gas': GAS_LIMIT_OP,
            'gasPrice': gas_price,
            'chainId': 11155420,
            'data': '0x' + account_info["address"][2:].lower().rjust(64, '0')
        }

        signed_tx = w3_op.eth.account.sign_transaction(tx, account_info["private_key"])
        tx_hash = w3_op.eth.send_raw_transaction(signed_tx.raw_transaction)
        tx_receipt = w3_op.eth.wait_for_transaction_receipt(tx_hash, timeout=180)

        if tx_receipt['status'] == 1:
            success_count += 1
            total_success_count += 1
            logger.info(f"{LIGHT_BLUE}{account_info['name']} OP -> UNI 成功{RESET}")
            send_telegram_notification(f"账户 {account_info['address']} OP -> UNI 跨链成功，交易哈希：{tx_hash.hex()}")
            return True
        else:
            logger.error(f"{account_info['name']} OP -> UNI 交易失败")
            send_telegram_notification(f"账户 {account_info['address']} OP -> UNI 交易失败")
            return False

    except Exception as e:
        logger.error(f"{account_info['name']} OP -> UNI 失败: {e}")
        send_telegram_notification(f"账户 {account_info['address']} OP -> UNI 失败：{str(e)}")
        return False

def main():
    """主函数"""
    load_config()
    
    if not ACCOUNTS:
        logger.error("账户列表为空")
        return

    logger.info(f"加载了 {len(ACCOUNTS)} 个账户")
    
    while True:
        for account in ACCOUNTS:
            try:
                bridge_op_to_uni(account)
            except Exception as e:
                logger.error(f"处理账户 {account['name']} 时出错: {e}")
            
            # 随机等待时间
            sleep_time = MIN_INTERVAL + (MAX_INTERVAL - MIN_INTERVAL) * (hash(str(time.time())) % 100) / 100
            time.sleep(sleep_time)

if __name__ == "__main__":
    main() 
