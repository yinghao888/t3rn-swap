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
OP_CONTRACT_ADDRESS = "0xb6Def636914Ae60173d9007E732684a9eEDEF26E"

# === RPC 配置 ===
ARB_RPC_URLS = [
    "https://sepolia-arbitrum.publicnode.com",
    "https://arbitrum-sepolia.blockpi.network/v1/rpc/public",
    "https://arbitrum-sepolia.public.blastapi.io"
]

OP_RPC_URLS = [
    "https://sepolia.optimism.io",
    "https://optimism-sepolia.drpc.org"
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
    
    logging.info("开始检测 Optimism Sepolia RPC...")
    op_rpcs = test_rpc_connectivity(OP_RPC_URLS, "Optimism Sepolia")
    if not op_rpcs:
        raise Exception("没有可用的 Optimism Sepolia RPC")
    
    return (
        Web3(Web3.HTTPProvider(arb_rpcs[0])),
        Web3(Web3.HTTPProvider(op_rpcs[0]))
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

def create_data_for_arb_to_op(address):
    """根据用户地址创建ARB到OP的交易数据"""
    # 去除地址前缀0x
    address_no_prefix = address[2:] if address.startswith("0x") else address
    
    # 构建数据模板 - 在中间部分插入用户地址
    data = f"0x56591d596f707374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address_no_prefix}0000000000000000000000000000000000000000000000000de0689a8072b11a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
    
    return data

def create_data_for_op_to_arb(address):
    """根据用户地址创建OP到ARB的交易数据"""
    # 去除地址前缀0x
    address_no_prefix = address[2:] if address.startswith("0x") else address
    
    # 构建数据模板 - 在中间部分插入用户地址
    data = f"0x56591d5961726274000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address_no_prefix}0000000000000000000000000000000000000000000000000ddfc5981fd8e21a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000"
    
    return data

def bridge_arb_to_op(w3_arb, account, amount_eth):
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

def bridge_op_to_arb(w3_op, account, amount_eth):
    """从 Optimism 跨到 Arbitrum"""
    try:
        amount_wei = w3_op.to_wei(amount_eth, 'ether')
        nonce = w3_op.eth.get_transaction_count(account['address'])
        
        # 创建带有用户地址的数据
        data = create_data_for_op_to_arb(account['address'])
        
        tx = {
            'from': account['address'],
            'to': OP_CONTRACT_ADDRESS,
            'value': amount_wei,
            'nonce': nonce,
            'gas': 250000,
            'gasPrice': w3_op.to_wei(0.1, 'gwei'),
            'chainId': 11155420,
            'data': data
        }
        
        signed_tx = w3_op.eth.account.sign_transaction(tx, account['private_key'])
        tx_hash = w3_op.eth.send_raw_transaction(signed_tx.rawTransaction)
        logging.info(f"OP -> ARB 跨链交易已发送，交易哈希: {w3_op.to_hex(tx_hash)}")
        
        tx_receipt = w3_op.eth.wait_for_transaction_receipt(tx_hash)
        logging.info(f"交易已确认，区块号: {tx_receipt['blockNumber']}")
        return True
        
    except Exception as e:
        logging.error(f"OP -> ARB 跨链失败: {str(e)}")
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
    w3_arb, w3_op = initialize_web3()
    
    # 加载并初始化账户
    if ACCOUNTS:
        accounts_config = ACCOUNTS
    else:
        accounts_config = load_accounts()
    
    accounts = initialize_accounts(w3_arb, accounts_config)
    
    if not accounts:
        logging.error("没有可用账户")
        return
    
    logging.info(f"开始为 {len(accounts)} 个账户执行 ARB-OP 无限循环跨链，每次 1 ETH")
    
    # 检查方向配置
    direction = "arb_op"
    try:
        if os.path.exists("direction.conf"):
            with open("direction.conf", "r") as f:
                direction = f.read().strip()
    except:
        pass
    
    while True:
        for account in accounts:
            try:
                if direction == "arb_op":
                    # ARB -> OP
                    if bridge_arb_to_op(w3_arb, account, 1):
                        # 等待 0.5 秒
                        logging.info(f"等待 0.5 秒...")
                        time.sleep(0.5)
                        
                        # OP -> ARB
                        if bridge_op_to_arb(w3_op, account, 1):
                            # 等待 0.5 秒
                            logging.info(f"等待 0.5 秒...")
                            time.sleep(0.5)
                    
            except Exception as e:
                logging.error(f"账户 {account['name']} 跨链出错: {str(e)}")
                time.sleep(0.5)
                continue

if __name__ == "__main__":
    main() 