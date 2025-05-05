from web3 import Web3
import time
import random
import json
import logging
import os
from datetime import datetime

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

# === 合约地址和数据模板 ===
UNI_CONTRACT_ADDRESS = "0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9"
BASE_CONTRACT_ADDRESS = "0xCEE0372632a37Ba4d0499D1E2116eCff3A17d3C3"

# === RPC 配置 ===
UNI_RPC_URLS = [
    "https://unichain-sepolia-rpc.publicnode.com",
    "https://unichain-sepolia.drpc.org"
]

BASE_RPC_URLS = [
    "https://sepolia.base.org",
    "https://base-sepolia.blockpi.network/v1/rpc/public",
    "https://base-sepolia.public.blastapi.io"
]

def test_rpc_connectivity(rpc_urls, network_name):
    """测试 RPC 连接并返回可用的 RPC"""
    working_rpcs = []
    for rpc in rpc_urls:
        try:
            logging.info(f"开始检测 RPC: {rpc}")
            w3 = Web3(Web3.HTTPProvider(rpc))
            if w3.is_connected():
                working_rpcs.append(rpc)
                logging.info(f"RPC {rpc} 连接成功")
            else:
                logging.warning(f"RPC {rpc} 连接失败")
        except Exception as e:
            logging.error(f"RPC {rpc} 测试出错: {str(e)}")
    return working_rpcs

def initialize_web3():
    """初始化并返回可用的 Web3 实例"""
    logging.info("开始检测 Unichain Sepolia RPC...")
    uni_rpcs = test_rpc_connectivity(UNI_RPC_URLS, "Unichain Sepolia")
    if not uni_rpcs:
        raise Exception("没有可用的 Unichain Sepolia RPC")
    
    logging.info("开始检测 Base Sepolia RPC...")
    base_rpcs = test_rpc_connectivity(BASE_RPC_URLS, "Base Sepolia")
    if not base_rpcs:
        raise Exception("没有可用的 Base Sepolia RPC")
    
    return (
        Web3(Web3.HTTPProvider(uni_rpcs[0])),
        Web3(Web3.HTTPProvider(base_rpcs[0]))
    )

def load_accounts():
    """加载账户配置"""
    try:
        with open('accounts.json', 'r') as f:
            accounts = json.load(f)
        logging.info(f"加载账户列表：{accounts}")
        return accounts
    except Exception as e:
        logging.error(f"加载账户配置失败: {str(e)}")
        return []

# 定义ACCOUNTS变量，会被bridge-bot.sh脚本自动更新
ACCOUNTS = []

def create_data_for_uni_to_base(address):
    """根据用户地址创建UNI到BASE的交易数据"""
    # 去除地址前缀0x
    address_no_prefix = address[2:] if address.startswith("0x") else address
    
    # 构建数据模板 - 在中间部分插入用户地址
    data = f"0x56591d5962617374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address_no_prefix}0000000000000000000000000000000000000000000000000de0933e57d20ab9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
    
    return data

def create_data_for_base_to_uni(address):
    """根据用户地址创建BASE到UNI的交易数据"""
    # 去除地址前缀0x
    address_no_prefix = address[2:] if address.startswith("0x") else address
    
    # 构建数据模板 - 在中间部分插入用户地址
    data = f"0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address_no_prefix}0000000000000000000000000000000000000000000000000de0933e5937a2ab000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
    
    return data

def bridge_uni_to_base(w3_uni, account, amount_eth):
    """从 Unichain 跨到 Base"""
    try:
        amount_wei = w3_uni.to_wei(amount_eth, 'ether')
        nonce = w3_uni.eth.get_transaction_count(account['address'])
        
        # 创建带有用户地址的数据
        data = create_data_for_uni_to_base(account['address'])
        
        tx = {
            'from': account['address'],
            'to': UNI_CONTRACT_ADDRESS,
            'value': amount_wei,
            'nonce': nonce,
            'gas': 400000,
            'gasPrice': w3_uni.to_wei(0.1, 'gwei'),
            'chainId': 1301,
            'data': data
        }
        
        signed_tx = w3_uni.eth.account.sign_transaction(tx, account['private_key'])
        tx_hash = w3_uni.eth.send_raw_transaction(signed_tx.rawTransaction)
        logging.info(f"UNI -> BASE 跨链交易已发送，交易哈希: {w3_uni.to_hex(tx_hash)}")
        
        tx_receipt = w3_uni.eth.wait_for_transaction_receipt(tx_hash)
        logging.info(f"交易已确认，区块号: {tx_receipt['blockNumber']}")
        return True
        
    except Exception as e:
        logging.error(f"UNI -> BASE 跨链失败: {str(e)}")
        return False

def bridge_base_to_uni(w3_base, account, amount_eth):
    """从 Base 跨到 Unichain"""
    try:
        amount_wei = w3_base.to_wei(amount_eth, 'ether')
        nonce = w3_base.eth.get_transaction_count(account['address'])
        
        # 创建带有用户地址的数据
        data = create_data_for_base_to_uni(account['address'])
        
        tx = {
            'from': account['address'],
            'to': BASE_CONTRACT_ADDRESS,
            'value': amount_wei,
            'nonce': nonce,
            'gas': 250000,
            'gasPrice': w3_base.to_wei(0.1, 'gwei'),
            'chainId': 84532,
            'data': data
        }
        
        signed_tx = w3_base.eth.account.sign_transaction(tx, account['private_key'])
        tx_hash = w3_base.eth.send_raw_transaction(signed_tx.rawTransaction)
        logging.info(f"BASE -> UNI 跨链交易已发送，交易哈希: {w3_base.to_hex(tx_hash)}")
        
        tx_receipt = w3_base.eth.wait_for_transaction_receipt(tx_hash)
        logging.info(f"交易已确认，区块号: {tx_receipt['blockNumber']}")
        return True
        
    except Exception as e:
        logging.error(f"BASE -> UNI 跨链失败: {str(e)}")
        return False

def initialize_accounts(w3_uni, accounts_config):
    """初始化账户"""
    initialized_accounts = []
    for acc in accounts_config:
        try:
            account = w3_uni.eth.account.from_key(acc['private_key'])
            initialized_accounts.append({
                'private_key': acc['private_key'],
                'address': account.address,
                'name': acc['name']
            })
            logging.info(f"成功初始化账户 {acc['name']}，地址：{account.address}")
        except Exception as e:
            logging.error(f"初始化账户失败: {str(e)}")
    return initialized_accounts

def main():
    # 初始化 Web3 连接
    w3_uni, w3_base = initialize_web3()
    
    # 加载并初始化账户
    if ACCOUNTS:
        accounts_config = ACCOUNTS
    else:
        accounts_config = load_accounts()
    
    accounts = initialize_accounts(w3_uni, accounts_config)
    
    if not accounts:
        logging.error("没有可用账户")
        return
    
    logging.info(f"开始为 {len(accounts)} 个账户执行 UNI-BASE 无限循环跨链，每次 1 ETH")
    
    # 检查方向配置
    direction = "uni_base"
    try:
        if os.path.exists("direction.conf"):
            with open("direction.conf", "r") as f:
                direction = f.read().strip()
    except:
        pass
    
    while True:
        for account in accounts:
            try:
                if direction == "uni_base":
                    # UNI -> BASE
                    if bridge_uni_to_base(w3_uni, account, 1):
                        # 等待 0.5 秒
                        logging.info(f"等待 0.5 秒...")
                        time.sleep(0.5)
                        
                        # BASE -> UNI
                        if bridge_base_to_uni(w3_base, account, 1):
                            # 等待 0.5 秒
                            logging.info(f"等待 0.5 秒...")
                            time.sleep(0.5)
                    
            except Exception as e:
                logging.error(f"账户 {account['name']} 跨链出错: {str(e)}")
                time.sleep(0.5)
                continue

if __name__ == "__main__":
    main() 