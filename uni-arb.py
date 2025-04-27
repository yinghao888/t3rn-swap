from web3 import Web3
import time
from typing import List, Dict
import logging
from concurrent.futures import ThreadPoolExecutor
import os
import telegram
import json

# === ANSI 颜色代码 ===
LIGHT_BLUE = "\033[96m"
LIGHT_RED = "\033[95m"
RESET = "\033[0m"

# === 配置日志 ===
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger()

# === 可自定义参数 ===
ACCOUNTS = []
AMOUNT_ETH = 1  # 每次跨链金额（单位：ETH）
REQUEST_INTERVAL = 1  # 同一方向请求间隔（秒）

# Arbitrum Sepolia 测试网 RPC 配置
ARB_RPC_URLS = [
    "https://arbitrum-sepolia-rpc.publicnode.com",
    "https://sepolia-rollup.arbitrum.io/rpc",
    "https://arbitrum-sepolia.drpc.org",
]

# Unichain Sepolia 测试网 RPC 配置
UNI_RPC_URLS = [
    "https://unichain-sepolia-rpc.publicnode.com",
    "https://unichain-sepolia.drpc.org",
]

# 合约地址
UNI_TO_ARB_CONTRACT = "0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9"
ARB_TO_UNI_CONTRACT = "0x22B65d0B9b59af4D3Ed59F18b9Ad53f5F4908B54"

# 数据模板
UNI_TO_ARB_DATA_TEMPLATE = "0x56591d5961726274000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de08e51f0c04e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
ARB_TO_UNI_DATA_TEMPLATE = "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de06a4dded38400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"

# 检测并过滤 RPC 的函数
def test_rpc_connectivity(rpc_urls: List[str], max_attempts: int = 5) -> List[str]:
    available_rpcs = []
    for url in rpc_urls:
        logger.info(f"开始检测 RPC: {url}")
        for attempt in range(max_attempts):
            try:
                w3 = Web3(Web3.HTTPProvider(url, request_kwargs={'timeout': 10}))
                if w3.is_connected():
                    logger.info(f"RPC {url} 连接成功")
                    available_rpcs.append(url)
                    break
                else:
                    logger.warning(f"RPC {url} 第 {attempt + 1} 次尝试失败")
            except Exception as e:
                logger.warning(f"RPC {url} 第 {attempt + 1} 次尝试失败: {e}")
            time.sleep(1)
        else:
            logger.error(f"RPC {url} 在 {max_attempts} 次尝试后仍不可用，已屏蔽")
    if not available_rpcs:
        logger.error("所有 RPC 均不可用，程序退出")
        exit(1)
    return available_rpcs

# 轮询初始化 Web3 实例的函数
def get_web3_instance(rpc_urls: List[str], chain_id: int) -> Web3:
    for url in rpc_urls:
        try:
            w3 = Web3(Web3.HTTPProvider(url, request_kwargs={'timeout': 10}))
            if w3.is_connected():
                return w3
            else:
                logger.warning(f"无法连接到 {url}")
        except Exception as e:
            logger.warning(f"连接 {url} 失败: {e}")
    raise Exception("所有可用 RPC 均不可用")

# 读取 Telegram Chat IDs
def get_chat_ids():
    if not os.path.exists('telegram.conf'):
        logger.warning("未找到 telegram.conf，未配置 Telegram 通知")
        return []
    try:
        with open('telegram.conf', 'r') as f:
            config = json.load(f)
        return config.get('chat_ids', [])
    except Exception as e:
        logger.error(f"读取 telegram.conf 失败: {e}")
        return []

# 优化参数
GAS_LIMIT_UNI = 200000
GAS_LIMIT_ARB = 200000
MIN_GAS_PRICE = Web3.to_wei(0.05, 'gwei')

# 全局计数器
success_count = 0
total_success_count = 0
start_time = time.time()

# 初始化并检测 RPC
logger.info("开始检测 Unichain Sepolia RPC...")
UNI_RPC_URLS = test_rpc_connectivity(UNI_RPC_URLS)
logger.info("开始检测 Arbitrum Sepolia RPC...")
ARB_RPC_URLS = test_rpc_connectivity(ARB_RPC_URLS)

# 账户初始化
accounts: List[Dict] = []
if not ACCOUNTS:
    logger.error("账户列表为空，请在 bridge-bot.sh 中添加私钥")
else:
    logger.info(f"加载账户列表：{ACCOUNTS}")
    for acc in ACCOUNTS:
        try:
            if not acc["private_key"]:
                logger.warning(f"账户 {acc['name']} 私钥为空，跳过")
                continue
            account = Web3(Web3.HTTPProvider(UNI_RPC_URLS[0])).eth.account.from_key(acc["private_key"])
            address = account.address[2:]
            accounts.append({
                "name": acc["name"],
                "private_key": acc["private_key"],
                "address": account.address,
                "address_no_prefix": address,
                "uni_data": UNI_TO_ARB_DATA_TEMPLATE.format(address=address),
                "arb_data": ARB_TO_UNI_DATA_TEMPLATE.format(address=address),
                "uni_pause_until": 0,
                "arb_pause_until": 0,
                "uni_to_arb_last": 0,
                "arb_to_uni_last": 0
            })
            logger.info(f"成功初始化账户 {acc['name']}，地址：{account.address}")
        except Exception as e:
            logger.error(f"初始化账户 {acc['name']} 失败: {e}")

# 获取动态 Gas Price
def get_dynamic_gas_price(w3_instance) -> int:
    try:
        latest_block = w3_instance.eth.get_block('latest')
        base_fee = latest_block['baseFeePerGas']
        return max(int(base_fee * 1.2), MIN_GAS_PRICE)
    except Exception as e:
        logger.warning(f"获取 Gas Price 失败，使用默认值: {e}")
        return MIN_GAS_PRICE

# UNI -> ARB 跨链函数
def bridge_uni_to_arb(account_info: Dict) -> bool:
    global success_count, total_success_count
    current_time = time.time()
    if current_time < account_info["uni_to_arb_last"] + REQUEST_INTERVAL:
        return False
    if current_time < account_info["uni_pause_until"]:
        return False
    try:
        w3_uni = get_web3_instance(UNI_RPC_URLS, chain_id=1301)
        amount_wei = w3_uni.to_wei(AMOUNT_ETH, 'ether')
        balance = w3_uni.eth.get_balance(account_info["address"])
        gas_price = get_dynamic_gas_price(w3_uni)
        total_cost = amount_wei + (gas_price * GAS_LIMIT_UNI)
        if balance < total_cost:
            logger.warning(f"{account_info['name']} UNI 余额不足，暂停 UNI -> ARB 1 分钟")
            account_info["uni_pause_until"] = time.time() + 60
            return False
        nonce = w3_uni.eth.get_transaction_count(account_info["address"])
        tx = {
            'from': account_info["address"],
            'to': UNI_TO_ARB_CONTRACT,
            'value': amount_wei,
            'nonce': nonce,
            'gas': GAS_LIMIT_UNI,
            'gasPrice': gas_price,
            'chainId': 1301,
            'data': account_info["uni_data"]
        }
        signed_tx = w3_uni.eth.account.sign_transaction(tx, account_info["private_key"])
        tx_hash = w3_uni.eth.send_raw_transaction(signed_tx.raw_transaction)
        tx_receipt = w3_uni.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
        success_count += 1
        total_success_count += 1
        account_info["uni_to_arb_last"] = current_time
        logger.info(f"{LIGHT_BLUE}{account_info['name']} UNI -> ARB 成功{RESET}")
        chat_ids = get_chat_ids()
        if chat_ids:
            bot = telegram.Bot(token="8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38")
            for chat_id in chat_ids:
                try:
                    bot.send_message(chat_id=chat_id, text=f"{account_info['name']} UNI -> ARB 跨链成功！")
                    logger.info(f"通知发送成功到 {chat_id}")
                except Exception as e:
                    logger.error(f"通知发送失败到 {chat_id}: {e}")
        return True
    except Exception as e:
        logger.error(f"{account_info['name']} UNI -> ARB 失败: {e}")
        return False

# ARB -> UNI 跨链函数
def bridge_arb_to_uni(account_info: Dict) -> bool:
    global success_count, total_success_count
    current_time = time.time()
    if current_time < account_info["arb_to_uni_last"] + REQUEST_INTERVAL:
        return False
    if current_time < account_info["arb_pause_until"]:
        return False
    try:
        w3_arb = get_web3_instance(ARB_RPC_URLS, chain_id=421614)
        amount_wei = w3_arb.to_wei(AMOUNT_ETH, 'ether')
        balance = w3_arb.eth.get_balance(account_info["address"])
        gas_price = get_dynamic_gas_price(w3_arb)
        total_cost = amount_wei + (gas_price * GAS_LIMIT_ARB)
        if balance < total_cost:
            logger.warning(f"{account_info['name']} ARB 余额不足，暂停 ARB -> UNI 1 分钟")
            account_info["arb_pause_until"] = time.time() + 60
            return False
        nonce = w3_arb.eth.get_transaction_count(account_info["address"])
        tx = {
            'from': account_info["address"],
            'to': ARB_TO_UNI_CONTRACT,
            'value': amount_wei,
            'nonce': nonce,
            'gas': GAS_LIMIT_ARB,
            'gasPrice': gas_price,
            'chainId': 421614,
            'data': account_info["arb_data"]
        }
        signed_tx = w3_arb.eth.account.sign_transaction(tx, account_info["private_key"])
        tx_hash = w3_arb.eth.send_raw_transaction(signed_tx.raw_transaction)
        tx_receipt = w3_arb.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
        success_count += 1
        total_success_count += 1
        account_info["arb_to_uni_last"] = current_time
        logger.info(f"{LIGHT_RED}{account_info['name']} ARB -> UNI 成功{RESET}")
        chat_ids = get_chat_ids()
        if chat_ids:
            bot = telegram.Bot(token="8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38")
            for chat_id in chat_ids:
                try:
                    bot.send_message(chat_id=chat_id, text=f"{account_info['name']} ARB -> UNI 跨链成功！")
                    logger.info(f"通知发送成功到 {chat_id}")
                except Exception as e:
                    logger.error(f"通知发送失败到 {chat_id}: {e}")
        return True
    except Exception as e:
        logger.error(f"{account_info['name']} ARB -> UNI 失败: {e}")
        return False

# 并行执行跨链
def process_account(account_info: Dict):
    direction = open("direction.conf", "r").read().strip()
    while True:
        if direction == "arb_to_uni":
            bridge_arb_to_uni(account_info)
            bridge_uni_to_arb(account_info)

# 主函数
def main():
    if not accounts:
        logger.error("没有可用的账户，退出程序")
        return
    logger.info(f"开始为 {len(accounts)} 个账户执行 UNI-ARB 无限循环跨链，每次 {AMOUNT_ETH} ETH")
    with ThreadPoolExecutor(max_workers=min(len(accounts), 30)) as executor:
        executor.map(process_account, accounts)

if __name__ == "__main__":
    main()
