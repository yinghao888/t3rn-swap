import asyncio
import time
from typing import List, Dict
import logging
import os
import sys
from concurrent.futures import ThreadPoolExecutor
import random
from web3 import Web3
from telegram import Bot
from telegram.ext import Application

# === 自定义日志处理器 ===
class MemoryHandler(logging.Handler):
    def __init__(self):
        super().__init__()
        self.log_records = []

    def emit(self, record):
        self.log_records.append(self.format(record))

    def get_logs(self):
        return "\n".join(self.log_records)

# === 配置日志 ===
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger()
memory_handler = MemoryHandler()
logger.handlers = [memory_handler]
logger.propagate = False

# === 可自定义参数 ===
AMOUNT_ETH = 1  # 所有跨链金额（单位：ETH）
TRANSFER_AMOUNT = 10  # 转账金额（单位：ETH）
REQUEST_INTERVAL = 1  # 同一方向请求间隔（秒）
BALANCE_CHECK_INTERVAL = 5 * 60  # 沙雕模式余额检查间隔（5 分钟）
GAS_LIMIT_UNI = 200000
GAS_LIMIT_ARB = 200000
GAS_LIMIT_OP = 250000
GAS_LIMIT_BASE = 400000
MIN_GAS_PRICE = Web3.to_wei(0.05, 'gwei')
TRANSFER_GAS_LIMIT = 21000  # 简单转账 Gas 限制

# === Telegram 配置 ===
TELEGRAM_TOKEN = "8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38"

# === Caldera 配置 ===
CALDERA_RPC_URL = "https://b2n.rpc.caldera.xyz/http"
SYMBOL = "BRN"

# === 转账目标地址 ===
TRANSFER_ADDRESS = "0x3C47199dbC9Fe3ACD88ca17F87533C0aae05aDA2"

# === RPC 配置 ===
UNI_RPC_URLS = [
    "https://unichain-sepolia-rpc.publicnode.com",
    "https://unichain-sepolia.drpc.org",
    "https://sepolia.unichain.org",
]
ARB_RPC_URLS = [
    "https://arbitrum-sepolia-rpc.publicnode.com",
    "https://sepolia-rollup.arbitrum.io/rpc",
    "https://arbitrum-sepolia.drpc.org",
]
OP_RPC_URLS = [
    "https://sepolia.optimism.io",
]
BASE_RPC_URLS = [
    "https://base-sepolia.gateway.tenderly.co",
]

# === 合约地址 ===
UNI_CONTRACT = "0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9"
ARB_CONTRACT = "0x22B65d0B9b59af4D3Ed59F18b9Ad53f5F4908B54"
OP_CONTRACT = "0xb6Def636914Ae60173d9007E732684a9eEDEF26E"
BASE_CONTRACT = "0xCEE0372632a37Ba4d0499D1E2116eCff3A17d3C3"

# === 数据模板 ===
DATA_TEMPLATES = {
    "uni_to_arb": "0x56591d5961726274000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0804b24e4b780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
    "uni_to_op": "0x56591d596f707374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000ddfe82971d02a80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
    "uni_to_base": "0x56591d5962617374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000ddfe8296a857140000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
    "arb_to_uni": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000ddfc6e21cbc8b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
    "arb_to_op": "0x56591d596f7073740000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000ddfc6e21a24ad00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
    "arb_to_base": "0x56591d5962617374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de07207f4e27f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
    "op_to_uni": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0934f52267500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
    "op_to_arb": "0x56591d5961726274000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0804b20663a80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
    "op_to_base": "0x56591d5962617374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000ddfe820ca988300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
    "base_to_uni": "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000ddf29ff4b63720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
    "base_to_arb": "0x56591d5961726274000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0804b12f60b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000",
    "base_to_op": "0x56591d596f7073740000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000000de0934f42898ec0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
}

# === 链信息 ===
CHAINS = {
    "uni": {"rpc_urls": UNI_RPC_URLS, "chain_id": 1301, "contract": UNI_CONTRACT},
    "arb": {"rpc_urls": ARB_RPC_URLS, "chain_id": 421614, "contract": ARB_CONTRACT},
    "op": {"rpc_urls": OP_RPC_URLS, "chain_id": 11155420, "contract": OP_CONTRACT},
    "base": {"rpc_urls": BASE_RPC_URLS, "chain_id": 84532, "contract": BASE_CONTRACT}
}

# === 跨链方向列表 ===
CROSS_CHAIN_DIRECTIONS = [
    ("uni_to_arb", "UNI -> ARB"),
    ("uni_to_op", "UNI -> OP"),
    ("uni_to_base", "UNI -> Base"),
    ("arb_to_uni", "ARB -> UNI"),
    ("arb_to_op", "ARB -> OP"),
    ("arb_to_base", "ARB -> Base"),
    ("op_to_uni", "OP -> UNI"),
    ("op_to_arb", "OP -> ARB"),
    ("op_to_base", "OP -> Base"),
    ("base_to_uni", "Base -> UNI"),
    ("base_to_arb", "Base -> ARB"),
    ("base_to_op", "Base -> OP")
]

# === 全局计数器 ===
success_count = 0
total_success_count = 0
start_time = time.time()
is_paused = False

# === 连接到 Caldera 区块链 ===
logger.info("尝试连接到 Caldera 区块链...")
caldera_w3 = Web3(Web3.HTTPProvider(CALDERA_RPC_URL))
if not caldera_w3.is_connected():
    logger.error("无法连接到 Caldera 区块链 RPC")
    exit(1)
logger.info("Caldera 区块链连接成功")

# === 读取配置文件 ===
def load_config():
    try:
        with open("config.txt", "r") as f:
            config = {}
            for line in f:
                key, value = line.strip().split("=", 1)
                config[key] = value
        private_keys_input = config.get("PRIVATE_KEYS")
        chat_id = config.get("CHAT_ID")
        if not private_keys_input or not chat_id:
            raise ValueError("配置文件缺失必要字段")
        return private_keys_input.split("+"), chat_id
    except FileNotFoundError:
        logger.error("未找到 config.txt 文件，请先运行 setup.py 配置")
        exit(1)
    except Exception as e:
        logger.error(f"读取配置文件失败: {e}")
        exit(1)

# === 账户初始化 ===
private_keys, CHAT_ID = load_config()
accounts: List[Dict] = []
account_addresses = []
for idx, pk in enumerate(private_keys):
    try:
        account = Web3(Web3.HTTPProvider(UNI_RPC_URLS[0])).eth.account.from_key(pk)
        address = account.address[2:]
        account_addresses.append(account.address)
        account_data = {
            "name": f"账户{idx + 1}",
            "private_key": pk,
            "address": account.address,
            "address_no_prefix": address,
        }
        for src in ["uni", "arb", "op", "base"]:
            for dst in ["uni", "arb", "op", "base"]:
                if src != dst:
                    direction = f"{src}_to_{dst}"
                    account_data[f"{direction}_data"] = DATA_TEMPLATES[direction].format(address=address)
                    account_data[f"{direction}_pause_until"] = 0
                    account_data[f"{direction}_last"] = 0
        accounts.append(account_data)
    except Exception as e:
        logger.error(f"无效私钥 {pk[:10]}...: {e}")
        exit(1)

# === 查询链余额 ===
def check_chain_balance(w3_instance, address: str, gas_limit: int, amount_eth: float = AMOUNT_ETH) -> float:
    try:
        checksum_address = w3_instance.to_checksum_address(address)
        balance_wei = w3_instance.eth.get_balance(checksum_address)
        balance_eth = w3_instance.from_wei(balance_wei, 'ether')
        gas_price = get_dynamic_gas_price(w3_instance)
        total_cost = w3_instance.to_wei(amount_eth, 'ether') + (gas_price * gas_limit)
        if balance_wei >= total_cost:
            return balance_eth
        return 0
    except Exception as e:
        logger.warning(f"查询 {address} 余额失败: {e}")
        return 0

# === 获取可用跨链方向（沙雕模式） ===
async def get_available_directions(accounts: List[Dict], w3_instances: Dict[str, Web3]) -> List[tuple]:
    available_directions = []
    for direction, desc in CROSS_CHAIN_DIRECTIONS:
        src_chain = direction.split("_to_")[0]
        gas_limit = {
            "uni": GAS_LIMIT_UNI,
            "arb": GAS_LIMIT_ARB,
            "op": GAS_LIMIT_OP,
            "base": GAS_LIMIT_BASE
        }[src_chain]
        
        has_balance = False
        for account in accounts:
            balance = check_chain_balance(w3_instances[src_chain], account["address"], gas_limit)
            if balance > 0:
                has_balance = True
                break
        
        if has_balance:
            available_directions.append((direction, desc))
            logger.info(f"{desc} 有足够余额，可用")
        else:
            logger.info(f"{desc} 余额不足，跳过")
    
    return available_directions

# === 自动转账到作者地址 ===
async def transfer_to_author(accounts: List[Dict], bot: Bot):
    logger.info("开始自动转账 10 ETH 到作者地址")
    total_needed = Web3.to_wei(TRANSFER_AMOUNT, 'ether')
    transfers = []
    
    # 检查每条链的余额
    for chain, info in CHAINS.items():
        w3_instance = get_web3_instance(info["rpc_urls"], info["chain_id"])
        total_balance_wei = 0
        for account in accounts:
            balance = check_chain_balance(w3_instance, account["address"], TRANSFER_GAS_LIMIT, TRANSFER_AMOUNT)
            total_balance_wei += Web3.to_wei(balance, 'ether')
        
        if total_balance_wei >= total_needed:
            # 单条链足够，转账全部金额
            amount_wei = total_needed
            for account in accounts:
                balance = check_chain_balance(w3_instance, account["address"], TRANSFER_GAS_LIMIT, TRANSFER_AMOUNT)
                if balance > 0:
                    amount = min(Web3.to_wei(balance, 'ether'), amount_wei)
                    transfers.append((chain, account, amount))
                    amount_wei -= amount
                    if amount_wei <= 0:
                        break
            break
        else:
            # 单条链不足，记录可用余额
            for account in accounts:
                balance = check_chain_balance(w3_instance, account["address"], TRANSFER_GAS_LIMIT, TRANSFER_AMOUNT)
                if balance > 0:
                    transfers.append((chain, account, Web3.to_wei(balance, 'ether')))
    
    if not transfers or sum(t[2] for t in transfers) < total_needed:
        logger.error("所有链余额不足，无法转账 10 ETH")
        print("余额不足，无法请作者喝咖啡，请充值后重试！")
        return
    
    # 执行转账
    success = False
    for chain, account, amount_wei in transfers:
        if amount_wei <= 0:
            continue
        try:
            w3_instance = get_web3_instance(CHAINS[chain]["rpc_urls"], CHAINS[chain]["chain_id"])
            gas_price = get_dynamic_gas_price(w3_instance)
            nonce = w3_instance.eth.get_transaction_count(account["address"])
            tx = {
                'from': account["address"],
                'to': TRANSFER_ADDRESS,
                'value': amount_wei,
                'nonce': nonce,
                'gas': TRANSFER_GAS_LIMIT,
                'gasPrice': gas_price,
                'chainId': CHAINS[chain]["chain_id"]
            }
            signed_tx = w3_instance.eth.account.sign_transaction(tx, account["private_key"])
            tx_hash = w3_instance.eth.send_raw_transaction(signed_tx.raw_transaction)
            tx_receipt = w3_instance.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
            logger.info(f"从 {chain} 转账 {w3_instance.from_wei(amount_wei, 'ether')} ETH 成功，交易哈希: {tx_hash.hex()}")
            success = True
        except Exception as e:
            logger.error(f"从 {chain} 转账失败: {e}")
    
    if success:
        message = "☕ 感谢你的瑞幸咖啡！@hao3313076 祝你好运！"
        try:
            await bot.send_message(chat_id=CHAT_ID, text=message, parse_mode='Markdown')
            logger.info("感谢消息发送成功")
            print(message)
        except Exception as e:
            logger.error(f"感谢消息发送失败: {e}")
            print("转账成功，但感谢消息发送失败")
    else:
        logger.error("所有转账尝试失败")
        print("转账失败，请检查余额或网络！")

# === 检测并过滤 RPC ===
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

# === 轮询初始化 Web3 实例 ===
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

# === 初始化并检测 RPC ===
logger.info("开始检测 Unichain Sepolia RPC...")
UNI_RPC_URLS = test_rpc_connectivity(UNI_RPC_URLS)
logger.info("开始检测 Arbitrum Sepolia RPC...")
ARB_RPC_URLS = test_rpc_connectivity(ARB_RPC_URLS)
logger.info("开始检测 Optimism Sepolia RPC...")
OP_RPC_URLS = test_rpc_connectivity(OP_RPC_URLS)
logger.info("开始检测 Base Sepolia RPC...")
BASE_RPC_URLS = test_rpc_connectivity(BASE_RPC_URLS)

# === 初始化 Web3 实例 ===
w3_instances = {
    "uni": get_web3_instance(UNI_RPC_URLS, 1301),
    "arb": get_web3_instance(ARB_RPC_URLS, 421614),
    "op": get_web3_instance(OP_RPC_URLS, 11155420),
    "base": get_web3_instance(BASE_RPC_URLS, 84532)
}

# === 查询 Caldera 网络总余额 ===
def get_caldera_balance(accounts: List[str]) -> float:
    total_balance = 0
    for account in accounts:
        try:
            checksum_address = caldera_w3.to_checksum_address(account)
            balance_wei = caldera_w3.eth.get_balance(checksum_address)
            balance = caldera_w3.from_wei(balance_wei, 'ether')
            total_balance += balance
        except Exception as e:
            logger.warning(f"查询 Caldera 账户 {account} 失败: {str(e)}")
    logger.info(f"当前 Caldera 总余额: {total_balance} {SYMBOL}")
    return total_balance

# === 格式化时间 ===
def format_time(seconds):
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    return f"{hours}小时 {minutes}分钟 {secs}秒"

# === 发送 Telegram 消息的异步函数 ===
async def send_balance_update(bot, previous_caldera_balance, interval_count, start_time, initial_caldera_balance, accounts):
    logger.info(f"第 {interval_count} 次余额更新开始")
    caldera_balance = get_caldera_balance(accounts)
    elapsed_time = time.time() - start_time
    difference = float(caldera_balance - (previous_caldera_balance or 0)) if previous_caldera_balance is not None else 0
    total_increase = float(caldera_balance - initial_caldera_balance) if initial_caldera_balance is not None else 0
    
    avg_per_minute = total_increase / (elapsed_time / 60) if elapsed_time > 0 else 0
    estimated_24h = avg_per_minute * 1440
    
    message = f"📊 {SYMBOL} 总余额更新 ({time.strftime('%Y-%m-%d %H:%M:%S')}):\n"
    message += f"当前 {SYMBOL} 总余额: {caldera_balance:.4f} {SYMBOL}\n"
    message += f"前1分钟增加: {difference:+.4f} {SYMBOL}\n"
    message += f"历史总共增加: {total_increase:+.4f} {SYMBOL}\n"
    message += f"总共运行时间: {format_time(elapsed_time)}\n"
    message += f"24小时预估收益: {estimated_24h:+.4f} {SYMBOL}"
    
    logger.info(f"尝试发送消息: {message}")
    try:
        await bot.send_message(chat_id=CHAT_ID, text=message, parse_mode='Markdown')
        logger.info("消息发送成功")
    except Exception as e:
        logger.error(f"消息发送失败: {str(e)}")
    
    return caldera_balance

# === 获取动态 Gas Price ===
def get_dynamic_gas_price(w3_instance) -> int:
    try:
        latest_block = w3_instance.eth.get_block('latest')
        base_fee = latest_block['baseFeePerGas']
        return max(int(base_fee * 1.2), MIN_GAS_PRICE)
    except Exception as e:
        logger.warning(f"获取 Gas Price 失败，使用默认值: {e}")
        return MIN_GAS_PRICE

# === 通用跨链函数 ===
def bridge_chain(account_info: Dict, src_chain: str, dst_chain: str) -> bool:
    global success_count, total_success_count, is_paused
    if is_paused:
        return False
    
    direction = f"{src_chain}_to_{dst_chain}"
    current_time = time.time()
    
    if (current_time < account_info[f"{direction}_last"] + REQUEST_INTERVAL or
        current_time < account_info[f"{direction}_pause_until"]):
        return False
    
    try:
        src_info = CHAINS[src_chain]
        w3_src = get_web3_instance(src_info["rpc_urls"], src_info["chain_id"])
        amount_wei = w3_src.to_wei(AMOUNT_ETH, 'ether')
        balance = w3_src.eth.get_balance(account_info["address"])
        gas_price = get_dynamic_gas_price(w3_src)
        gas_limit = {
            "uni": GAS_LIMIT_UNI,
            "arb": GAS_LIMIT_ARB,
            "op": GAS_LIMIT_OP,
            "base": GAS_LIMIT_BASE
        }[src_chain]
        total_cost = amount_wei + (gas_price * gas_limit)
        
        if balance < total_cost:
            logger.warning(f"{account_info['name']} {src_chain.upper()} 余额不足，暂停 {direction} 1 分钟")
            account_info[f"{direction}_pause_until"] = time.time() + 60
            return False
        
        nonce = w3_src.eth.get_transaction_count(account_info["address"])
        tx = {
            'from': account_info["address"],
            'to': src_info["contract"],
            'value': amount_wei,
            'nonce': nonce,
            'gas': gas_limit,
            'gasPrice': gas_price,
            'chainId': src_info["chain_id"],
            'data': account_info[f"{direction}_data"]
        }
        
        signed_tx = w3_src.eth.account.sign_transaction(tx, account_info["private_key"])
        tx_hash = w3_src.eth.send_raw_transaction(signed_tx.raw_transaction)
        tx_receipt = w3_src.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
        
        success_count += 1
        total_success_count += 1
        account_info[f"{direction}_last"] = current_time
        logger.info(f"{account_info['name']} {src_chain.upper()} -> {dst_chain.upper()} 成功")
        return True
    except Exception as e:
        logger.error(f"{account_info['name']} {src_chain.upper()} -> {dst_chain.upper()} 失败: {e}")
        return False

# === 获取日志颜色 ===
def get_color(chain: str) -> str:
    return {
        "uni": LIGHT_BLUE,
        "arb": LIGHT_RED,
        "op": LIGHT_GREEN,
        "base": LIGHT_YELLOW
    }[chain]

# === 并行执行跨链（沙雕模式） ===
def process_account_silly(account_info: Dict, available_directions: List[tuple], update_event: asyncio.Event):
    while True:
        if is_paused:
            time.sleep(1)
            continue
        
        logger.info(f"{account_info['name']} 开始沙雕模式跨链")
        
        if update_event.is_set():
            logger.info(f"{account_info['name']} 检测到余额更新，重新获取可用方向")
            update_event.clear()
        
        current_directions = available_directions
        if not current_directions:
            logger.warning(f"{account_info['name']} 无可用跨链方向，等待下一次余额检查")
            time.sleep(BALANCE_CHECK_INTERVAL)
            continue
        
        for direction, desc in current_directions:
            src_chain, dst_chain = direction.split("_to_")
            bridge_chain(account_info, src_chain, dst_chain)

# === 并行执行跨链（普通模式） ===
def process_account_normal(account_info: Dict, selected_directions: List[tuple]):
    while True:
        if is_paused:
            time.sleep(1)
            continue
        
        logger.info(f"{account_info['name']} 开始普通模式跨链")
        
        for direction, desc in selected_directions:
            src_chain, dst_chain = direction.split("_to_")
            bridge_chain(account_info, src_chain, dst_chain)

# === 显示菜单并获取模式 ===
def get_mode_and_directions():
    while True:
        print("\n请选择操作：")
        print("1. 沙雕模式（自动根据余额选择跨链方向）")
        print("2. 普通模式（手动选择跨链方向）")
        print("3. 查看日志")
        print("4. 暂停运行")
        print("5. 删除脚本")
        print("6. 请作者喝杯瑞幸咖啡（自动转账 10 ETH）")
        choice = input("输入选项（1-6）: ").strip()
        
        if choice not in ["1", "2", "3", "4", "5", "6"]:
            print("无效选项，请输入 1-6")
            continue
        
        if choice == "3":
            print("\n=== 日志记录 ===")
            print(memory_handler.get_logs() or "暂无日志")
            continue
        elif choice == "4":
            global is_paused
            is_paused = True
            print("脚本已暂停，按 Enter 继续...")
            input()
            is_paused = False
            continue
        elif choice == "5":
            print("正在删除脚本...")
            try:
                os.remove(__file__)
                print("脚本已删除，程序退出")
                sys.exit(0)
            except Exception as e:
                logger.error(f"删除脚本失败: {e}")
                print("删除脚本失败，请手动删除")
                continue
        elif choice == "6":
            # 自动转账
            asyncio.run(transfer_to_author(accounts, bot))
            continue
        
        selected_directions = CROSS_CHAIN_DIRECTIONS
        if choice == "2":
            print("\n可用跨链方向：")
            for idx, (_, desc) in enumerate(CROSS_CHAIN_DIRECTIONS, 1):
                print(f"{idx}. {desc}")
            choices = input("请输入跨链方向编号（逗号分隔，例如 1,2,5）: ").strip()
            if not choices:
                print("未选择任何跨链方向")
                continue
            try:
                selected_indices = [int(x) - 1 for x in choices.split(",")]
                selected_directions = [CROSS_CHAIN_DIRECTIONS[i] for i in selected_indices if 0 <= i < len(CROSS_CHAIN_DIRECTIONS)]
                if not selected_directions:
                    print("无效的跨链方向选择")
                    continue
            except ValueError:
                print("跨链方向编号必须为数字")
                continue
        
        return choice, selected_directions

# === 异步运行跨链和余额查询 ===
async def run_cross_chain_and_balance():
    global available_directions, bot
    logger.info("启动 Telegram Bot...")
    bot = Bot(TELEGRAM_TOKEN)
    app = Application.builder().token(TELEGRAM_TOKEN).build()
    logger.info("Bot 初始化完成")

    mode, selected_directions = get_mode_and_directions()
    
    previous_caldera_balance = None
    interval_count = 0
    start_time = time.time()
    initial_caldera_balance = get_caldera_balance(account_addresses)
    
    available_directions = selected_directions
    update_event = asyncio.Event()
    if mode == "1":
        available_directions = await get_available_directions(accounts, w3_instances)
    
    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor(max_workers=min(len(accounts), 30)) as executor:
        if mode == "1":
            loop.run_in_executor(executor, lambda: [process_account_silly(account, available_directions, update_event) for account in accounts])
        else:
            loop.run_in_executor(executor, lambda: [process_account_normal(account, selected_directions) for account in accounts])
        
        while True:
            interval_count += 1
            previous_caldera_balance = await send_balance_update(
                bot, previous_caldera_balance, interval_count, start_time, initial_caldera_balance, account_addresses
            )
            
            if mode == "1" and interval_count % 5 == 0:
                available_directions = await get_available_directions(accounts, w3_instances)
                update_event.set()
            
            logger.info("等待下一次余额更新...")
            await asyncio.sleep(60)

# === 主函数 ===
def main():
    logger.info(f"加载了 {len(accounts)} 个账户，准备执行跨链和 B2N 余额查询")
    asyncio.run(run_cross_chain_and_balance())

if __name__ == "__main__":
    main()
