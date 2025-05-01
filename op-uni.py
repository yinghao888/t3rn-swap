from web3 import Web3
import time
import random
import json
import logging
from datetime import datetime

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

# === 合约地址和数据模板 ===
OP_CONTRACT_ADDRESS = "0xb6Def636914Ae60173d9007E732684a9eEDEF26E"
UNI_CONTRACT_ADDRESS = "0x1cEAb5967E5f078Fa0FEC3DFfD0394Af1fEeBCC9"

OP_DATA_TEMPLATE = "0x56591d59756e6974000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000008ac706d26a14960c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008ac7230489e80000"

UNI_DATA_TEMPLATE = "0x56591d596f707374000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000{address}0000000000000000000000000000000000000000000000008ac706d5abff274a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008ac7230489e80000"

# === RPC 配置 ===
OP_RPC_URLS = [
    "https://sepolia.optimism.io",
    "https://optimism-sepolia.drpc.org"
]

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
    logging.info("开始检测 OP Sepolia RPC...")
    op_rpcs = test_rpc_connectivity(OP_RPC_URLS, "OP Sepolia")
    if not op_rpcs:
        raise Exception("没有可用的 OP Sepolia RPC")
    
    logging.info("开始检测 Unichain Sepolia RPC...")
    uni_rpcs = test_rpc_connectivity(UNI_RPC_URLS, "Unichain Sepolia")
    if not uni_rpcs:
        raise Exception("没有可用的 Unichain Sepolia RPC")
    
    return (
        Web3(Web3.HTTPProvider(op_rpcs[0])),
        Web3(Web3.HTTPProvider(uni_rpcs[0]))
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

def bridge_op_to_uni(w3_op, account, amount_eth):
    """从 OP 跨到 UNI"""
    try:
        account_address = account['address'][2:]  # 去掉 0x 前缀
        op_data = OP_DATA_TEMPLATE.format(address=account_address)
        amount_wei = w3_op.to_wei(amount_eth, 'ether')
        nonce = w3_op.eth.get_transaction_count(account['address'])
        
        tx = {
            'from': account['address'],
            'to': OP_CONTRACT_ADDRESS,
            'value': amount_wei,
            'nonce': nonce,
            'gas': 250000,
            'gasPrice': w3_op.to_wei(0.1, 'gwei'),
            'chainId': 11155420,
            'data': op_data
        }
        
        signed_tx = w3_op.eth.account.sign_transaction(tx, account['private_key'])
        tx_hash = w3_op.eth.send_raw_transaction(signed_tx.rawTransaction)
        logging.info(f"OP -> UNI 跨链交易已发送，交易哈希: {w3_op.to_hex(tx_hash)}")
        
        tx_receipt = w3_op.eth.wait_for_transaction_receipt(tx_hash)
        logging.info(f"交易已确认，区块号: {tx_receipt['blockNumber']}")
        return True
        
    except Exception as e:
        logging.error(f"OP -> UNI 跨链失败: {str(e)}")
        return False

def bridge_uni_to_op(w3_uni, account, amount_eth):
    """从 UNI 跨回 OP"""
    try:
        account_address = account['address'][2:]  # 去掉 0x 前缀
        uni_data = UNI_DATA_TEMPLATE.format(address=account_address)
        amount_wei = w3_uni.to_wei(amount_eth, 'ether')
        nonce = w3_uni.eth.get_transaction_count(account['address'])
        
        tx = {
            'from': account['address'],
            'to': UNI_CONTRACT_ADDRESS,
            'value': amount_wei,
            'nonce': nonce,
            'gas': 400000,
            'gasPrice': w3_uni.to_wei(0.1, 'gwei'),
            'chainId': 1301,
            'data': uni_data
        }
        
        signed_tx = w3_uni.eth.account.sign_transaction(tx, account['private_key'])
        tx_hash = w3_uni.eth.send_raw_transaction(signed_tx.rawTransaction)
        logging.info(f"UNI -> OP 跨链交易已发送，交易哈希: {w3_uni.to_hex(tx_hash)}")
        
        tx_receipt = w3_uni.eth.wait_for_transaction_receipt(tx_hash)
        logging.info(f"交易已确认，区块号: {tx_receipt['blockNumber']}")
        return True
        
    except Exception as e:
        logging.error(f"UNI -> OP 跨链失败: {str(e)}")
        return False

def initialize_accounts(w3_op, accounts_config):
    """初始化账户"""
    initialized_accounts = []
    for acc in accounts_config:
        try:
            account = w3_op.eth.account.from_key(acc['private_key'])
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
    w3_op, w3_uni = initialize_web3()
    
    # 加载并初始化账户
    accounts_config = load_accounts()
    accounts = initialize_accounts(w3_op, accounts_config)
    
    if not accounts:
        logging.error("没有可用账户")
        return
    
    logging.info(f"开始为 {len(accounts)} 个账户执行 OP-UNI 无限循环跨链，每次 1 ETH")
    
    while True:
        for account in accounts:
            try:
                # OP -> UNI
                if bridge_op_to_uni(w3_op, account, 1):
                    # 随机等待 5-10 秒
                    wait_time = random.randint(5, 10)
                    logging.info(f"等待 {wait_time} 秒...")
                    time.sleep(wait_time)
                    
                    # UNI -> OP
                    if bridge_uni_to_op(w3_uni, account, 1):
                        # 随机等待 5-10 秒
                        wait_time = random.randint(5, 10)
                        logging.info(f"等待 {wait_time} 秒...")
                        time.sleep(wait_time)
                    
            except Exception as e:
                logging.error(f"账户 {account['name']} 跨链出错: {str(e)}")
                time.sleep(5)
                continue

if __name__ == "__main__":
    main() 
