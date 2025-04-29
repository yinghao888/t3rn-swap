from web3 import Web3
import time
from typing import List, Dict
import logging
from concurrent.futures import ThreadPoolExecutor
import os
import json

# === ANSI 颜色代码 ===
LIGHT_BLUE = "\033[96m"
LIGHT_RED = "\033[95m"
RESET = "\033[0m"

# === 配置日志 ===
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger()

# 从 config.json 加载配置
with open("config.json", "r") as f:
    config = json.load(f)
REQUEST_INTERVAL = config["REQUEST_INTERVAL"]
AMOUNT_ETH = config["AMOUNT_ETH"]
OP_DATA_TEMPLATE = config["OP_DATA_TEMPLATE"]
UNI_DATA_TEMPLATE = config["UNI_DATA_TEMPLATE"]

# 从 rpc_config.json 加载 RPC 配置
with open("rpc_config.json", "r") as f:
    rpc_config = json.load(f)
OP_RPC_URLS = rpc_config["OP_RPC_URLS"]
UNI_RPC_URLS = rpc_config["UNI_RPC_URLS"]

# 合约地址
OP_CONTRACT_ADDRESS = "0xb6Def636914Ae60173d9007E732684a9eEDEF26E"
ARB_CONTRACT_ADDRESS = "0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9"

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

# 优化参数
GAS_LIMIT_OP = 250000
GAS_LIMIT_UNI = 400000
MIN_GAS_PRICE = Web3.to_wei(0.1, 'gwei')

# 全局计数器
success_count = 0
total_success_count = 0
start_time = time.time()

# 初始化并检测 RPC
logger.info("开始检测 OP Sepolia RPC...")
OP_RPC_URLS = test_rpc_connectivity(OP_RPC_URLS)
logger.info("开始检测 Unichain Sepolia RPC...")
UNI_RPC_URLS = test_rpc_connectivity(UNI_RPC_URLS)

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
            account = Web3(Web3.HTTPProvider(OP_RPC_URLS[0])).eth.account.from_key(acc["private_key"])
            address = account.address[2:]
            op_data = OP_DATA_TEMPLATE.format(address=address)
            accounts.append({
                "name": acc["name"],
                "private_key": acc["private_key"],
                "address": account.address,
                "address_no_prefix": address,
                "op_data": op_data.replace("6e6974", "61726274"),  # OP -> UNI
                "uni_data": UNI_DATA_TEMPLATE.format(address=address),  # UNI -> OP
                "op_pause_until": 0,
                "uni_pause_until": 0,
                "op_to_uni_last": 0,
                "uni_to_op_last": 0
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

# OP -> UNI 跨链函数
def bridge_op_to_uni(account_info: Dict) -> bool:
    global success_count, total_success_count
    current_time = time.time()
    if current_time < account_info["op_to_uni_last"] + REQUEST_INTERVAL:
        return False
    if current_time < account_info["op_pause_until"]:
        return False
    try:
        w3_op = get_web3_instance(OP_RPC_URLS, chain_id=11155420)
        amount_wei = w3_op.to_wei(AMOUNT_ETH, 'ether')
        balance = w3_op.eth.get_balance(account_info["address"])
        gas_price = get_dynamic_gas_price(w3_op)
        total_cost = amount_wei + (gas_price * GAS_LIMIT_OP)
        if balance < total_cost:
            logger.warning(f"{account_info['name']} OP 余额不足，暂停 OP -> UNI 1 分钟")
            account_info["op_pause_until"] = time.time() + 60
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
            'data': account_info["op_data"]
        }
        signed_tx = w3_op.eth.account.sign_transaction(tx, account_info["private_key"])
        tx_hash = w3_op.eth.send_raw_transaction(signed_tx.raw_transaction)
        tx_receipt = w3_op.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
        success_count += 1
        total_success_count += 1
        account_info["op_to_uni_last"] = current_time
        logger.info(f"{LIGHT_BLUE}{account_info['name']} OP -> UNI 成功{RESET}")
        return True
    except Exception as e:
        logger.error(f"{account_info['name']} OP -> UNI 失败: {e}")
        return False

# UNI -> OP 跨链函数
def bridge_uni_to_op(account_info: Dict) -> bool:
    global success_count, total_success_count
    current_time = time.time()
    if current_time < account_info["uni_to_op_last"] + REQUEST_INTERVAL:
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
            logger.warning(f"{account_info['name']} UNI 余额不足，暂停 UNI -> OP 1 分钟")
            account_info["uni_pause_until"] = time.time() + 60
            return False
        nonce = w3_uni.eth.get_transaction_count(account_info["address"])
        tx = {
            'from': account_info["address"],
            'to': ARB_CONTRACT_ADDRESS,
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
        account_info["uni_to_op_last"] = current_time
        logger.info(f"{LIGHT_RED}{account_info['name']} UNI -> OP 成功{RESET}")
        return True
    except Exception as e:
        logger.error(f"{account_info['name']} UNI -> OP 失败: {e}")
        return False

# 并行执行跨链
def process_account(account_info: Dict):
    direction = open("direction.conf", "r").read().strip()
    while True:
        if direction == "op_to_uni":
            bridge_op_to_uni(account_info)
            bridge_uni_to_op(account_info)

# 主函数
def main():
    if not accounts:
        logger.error("没有可用的账户，退出程序")
        return
    logger.info(f"开始为 {len(accounts)} 个账户执行 OP-UNI 无限循环跨链，每次 {AMOUNT_ETH} ETH")
    with ThreadPoolExecutor(max_workers=min(len(accounts), 30)) as executor:
        executor.map(process_account, accounts)

if __name__ == "__main__":
    main()
