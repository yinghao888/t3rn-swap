import asyncio
import time
from web3 import Web3
from telegram import Bot
import json
import os

# 配置
TELEGRAM_TOKEN = "8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38"
CONFIG_FILE = "accounts.json"
TELEGRAM_CONFIG = "telegram.conf"
CALDERA_RPC_URL = "https://b2n.rpc.caldera.xyz/http"
SYMBOL = "BRN"

# 读取 Telegram Chat ID
def get_chat_id():
    if not os.path.exists(TELEGRAM_CONFIG):
        print("警告：未配置 Telegram 用户 ID，请在 bridge-bot.sh 中选择 '1. 配置 Telegram' 输入 ID")
        return None
    with open(TELEGRAM_CONFIG, 'r') as f:
        return f.read().strip().split('=')[1]

# 读取账户列表并转换为地址
def get_accounts():
    if not os.path.exists(CONFIG_FILE):
        print("警告：未找到 accounts.json，请在 bridge-bot.sh 中添加私钥")
        return []
    try:
        with open(CONFIG_FILE, 'r') as f:
            accounts = json.load(f)
        if not isinstance(accounts, list):
            print("错误：accounts.json 格式无效，重置为空列表")
            with open(CONFIG_FILE, 'w') as f:
                json.dump([], f)
            return []
        return [{
            'name': account['name'],
            'address': Web3(Web3.HTTPProvider(CALDERA_RPC_URL)).eth.account.from_key(account['private_key']).address
        } for account in accounts]
    except json.JSONDecodeError as e:
        print(f"错误：accounts.json 解析失败 ({str(e)})，重置为空列表")
        with open(CONFIG_FILE, 'w') as f:
            json.dump([], f)
        return []

# 连接到 Caldera 区块链
print("尝试连接到 Caldera 区块链...")
caldera_w3 = Web3(Web3.HTTPProvider(CALDERA_RPC_URL))
if not caldera_w3.is_connected():
    raise Exception("无法连接到 Caldera 区块链 RPC")
print("Caldera 区块链连接成功")

# 查询 Caldera 网络总余额
def get_caldera_balance(accounts):
    total_balance = 0
    for account in accounts:
        try:
            checksum_address = caldera_w3.to_checksum_address(account['address'])
            balance_wei = caldera_w3.eth.get_balance(checksum_address)
            balance = caldera_w3.from_wei(balance_wei, 'ether')
            total_balance += balance
            print(f"账户 {account['name']} ({account['address'][:10]}...) 余额: {balance:.4f} {SYMBOL}")
        except Exception as e:
            print(f"查询 Caldera 账户 {account['name']} ({account['address'][:10]}...) 失败: {str(e)}")
    print(f"当前 Caldera 总余额: {total_balance:.4f} {SYMBOL}")
    return total_balance

# 格式化时间
def format_time(seconds):
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    return f"{hours}小时 {minutes}分钟 {secs}秒"

# 发送 Telegram 消息的异步函数
async def send_balance_update(bot, previous_caldera_balance, interval_count, start_time, initial_caldera_balance, accounts, chat_id):
    if chat_id is None:
        print("跳过 Telegram 通知：未配置 Chat ID")
        return previous_caldera_balance
    print(f"第 {interval_count} 次更新开始")
    caldera_balance = get_caldera_balance(accounts)
    elapsed_time = time.time() - start_time
    difference = float(caldera_balance - (previous_caldera_balance or 0)) if previous_caldera_balance is not None else 0
    total_increase = float(caldera_balance - initial_caldera_balance) if initial_caldera_balance is not None else 0
    
    # 计算 24 小时预估收益（24小时 = 1440分钟）
    avg_per_minute = total_increase / (elapsed_time / 60) if elapsed_time > 0 else 0
    estimated_24h = avg_per_minute * 1440
    
    message = f"📊 {SYMBOL} 总余额更新 ({time.strftime('%Y-%m-%d %H:%M:%S')}):\n"
    message += f"当前 {SYMBOL} 总余额: {caldera_balance:.4f} {SYMBOL}\n"
    message += f"前1分钟增加: {difference:+.4f} {SYMBOL}\n"
    message += f"历史总共增加: {total_increase:+.4f} {SYMBOL}\n"
    message += f"总共运行时间: {format_time(elapsed_time)}\n"
    message += f"24小时预估收益: {estimated_24h:+.4f} {SYMBOL}"
    
    print(f"尝试发送消息: {message}")
    try:
        await bot.send_message(chat_id=chat_id, text=message, parse_mode='Markdown')
        print("消息发送成功")
    except Exception as e:
        print(f"消息发送失败: {str(e)}")
    
    return caldera_balance

# 主循环
async def main():
    print("启动 Telegram Bot...")
    bot = Bot(TELEGRAM_TOKEN)
    chat_id = get_chat_id()
    accounts = get_accounts()
    
    previous_caldera_balance = None
    interval_count = 0
    start_time = time.time()
    initial_caldera_balance = get_caldera_balance(accounts)
    
    while True:
        interval_count += 1
        previous_caldera_balance = await send_balance_update(bot, previous_caldera_balance, interval_count, start_time, initial_caldera_balance, accounts, chat_id)
        print(f"等待下一次更新...")
        await asyncio.sleep(60)

if __name__ == "__main__":
    asyncio.run(main())
