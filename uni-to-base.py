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

# === RPC 配置 ===
UNI_RPC_URLS = [
    "https://unichain-sepolia-rpc.publicnode.com",
    "https://unichain-sepolia.drpc.org"
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
    
    return Web3(Web3.HTTPProvider(uni_rpcs[0]))

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
    """根据用户地址创建交易数据"""
    # 去除地址前缀0x
    address_no_prefix = address[2:] if address.startswith("0x") else address
    
    # 构建数据模板 - 在中间部分插入用户地址
    data = f"0x56591d5962617365000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address_no_prefix}0000000000000000000000000000000000000000000000003092467525c6a05c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030927f74c9de0000"
    
    return data

def bridge_uni_to_base(w3_uni, account, amount_eth=1):
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
    w3_uni = initialize_web3()
    
    # 加载并初始化账户
    if ACCOUNTS:
        accounts_config = ACCOUNTS
    else:
        accounts_config = load_accounts()
    
    accounts = initialize_accounts(w3_uni, accounts_config)
    
    if not accounts:
        logging.error("没有可用账户")
        return
    
    logging.info(f"开始为 {len(accounts)} 个账户执行 UNI->BASE 单向跨链，每次 5 ETH")
    
    # 循环执行单向跨链
    round_count = 0
    while True:
        round_count += 1
        logging.info(f"第 {round_count} 轮跨链开始")
        
        for account in accounts:
            try:
                # UNI -> BASE
                if bridge_uni_to_base(w3_uni, account, 5):
                    # 等待 1-2 秒
                    wait_time = random.uniform(1, 2)
                    logging.info(f"等待 {wait_time:.2f} 秒...")
                    time.sleep(wait_time)
                    
            except Exception as e:
                logging.error(f"账户 {account['name']} 跨链出错: {str(e)}")
                time.sleep(5)
                continue
                
        logging.info(f"第 {round_count} 轮跨链完成，等待 10 分钟后开始下一轮...")
        time.sleep(10 * 60)  # 等待 10 分钟

if __name__ == "__main__":
    main() 