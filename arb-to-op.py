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
ARB_CONTRACT_ADDRESS = "0x22B65d0B9b59af4D3Ed59F18b9Ad53f5F4908B54"

# === RPC 配置 ===
ARB_RPC_URLS = [
    "https://sepolia-arbitrum.publicnode.com",
    "https://arbitrum-sepolia.blockpi.network/v1/rpc/public",
    "https://arbitrum-sepolia.public.blastapi.io"
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
    logging.info("开始检测 Arbitrum Sepolia RPC...")
    arb_rpcs = test_rpc_connectivity(ARB_RPC_URLS, "Arbitrum Sepolia")
    if not arb_rpcs:
        raise Exception("没有可用的 Arbitrum Sepolia RPC")
    
    return Web3(Web3.HTTPProvider(arb_rpcs[0]))

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

def create_data_for_arb_to_op(address):
    """根据用户地址创建交易数据"""
    # 去除地址前缀0x
    address_no_prefix = address[2:] if address.startswith("0x") else address
    
    # 构建数据模板 - 在中间部分插入用户地址
    data = f"0x56591d596f707374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address_no_prefix}0000000000000000000000000000000000000000000000000de0689a8072b11a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
    
    return data

def bridge_arb_to_op(w3_arb, account, amount_eth=1):
    """从 Arbitrum 跨到 Optimism"""
    try:
        amount_wei = w3_arb.to_wei(amount_eth, 'ether')
        nonce = w3_arb.eth.get_transaction_count(account['address'])
        
        # 创建带有用户地址的数据
        data = create_data_for_arb_to_op(account['address'])
        
        tx = {
            'from': account['address'],
            'to': ARB_CONTRACT_ADDRESS,
            'value': amount_wei,
            'nonce': nonce,
            'gas': 250000,
            'gasPrice': w3_arb.to_wei(0.1, 'gwei'),
            'chainId': 421614,
            'data': data
        }
        
        signed_tx = w3_arb.eth.account.sign_transaction(tx, account['private_key'])
        tx_hash = w3_arb.eth.send_raw_transaction(signed_tx.rawTransaction)
        logging.info(f"ARB -> OP 跨链交易已发送，交易哈希: {w3_arb.to_hex(tx_hash)}")
        
        tx_receipt = w3_arb.eth.wait_for_transaction_receipt(tx_hash)
        logging.info(f"交易已确认，区块号: {tx_receipt['blockNumber']}")
        return True
        
    except Exception as e:
        logging.error(f"ARB -> OP 跨链失败: {str(e)}")
        return False

def initialize_accounts(w3_arb, accounts_config):
    """初始化账户"""
    initialized_accounts = []
    for acc in accounts_config:
        try:
            account = w3_arb.eth.account.from_key(acc['private_key'])
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
    w3_arb = initialize_web3()
    
    # 加载并初始化账户
    if ACCOUNTS:
        accounts_config = ACCOUNTS
    else:
        accounts_config = load_accounts()
    
    accounts = initialize_accounts(w3_arb, accounts_config)
    
    if not accounts:
        logging.error("没有可用账户")
        return
    
    logging.info(f"开始为 {len(accounts)} 个账户执行 ARB->OP 单向跨链，每次 5 ETH")
    
    # 循环执行单向跨链
    round_count = 0
    while True:
        round_count += 1
        logging.info(f"第 {round_count} 轮跨链开始")
        
        for account in accounts:
            try:
                # ARB -> OP
                if bridge_arb_to_op(w3_arb, account, 5):
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