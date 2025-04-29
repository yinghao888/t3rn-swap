```python
import asyncio
import time
from web3 import Web3
import json
import os

try:
    from telegram import Bot
except ImportError:
    print("错误：未安装 python-telegram-bot 库，请运行 'pip3 install python-telegram-bot==13.7'")
    exit(1)

# 配置
TELEGRAM_TOKEN = "8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38"
CONFIG_FILE = "accounts.json"
TELEGRAM_CONFIG = "telegram.conf"
CALDERA_RPC_URL = "https://b2n.rpc.caldera.xyz/http"
SYMBOL = "BRN"

# 读取 Telegram Chat IDs
def get_chat_ids():
    if not os.path.exists(TELEGRAM_CONFIG):
        print("警告：未配置 Telegram 用户 ID，请在 bridge-bot.sh 中选择 '1. 配置 Telegram' 输入 ID")
        return []
    try:
        with open(TELEGRAM_CONFIG, 'r') as f:
            config = json.load(f)
        if not isinstance(config, dict) or 'chat_ids' not in config or not isinstance(config['chat_ids'], list):
            print("错误：telegram.conf 格式无效，重置为空列表")
            with open(TELEGRAM_CONFIG, 'w') as f:
                json.dump({"chat_ids": []}, f)
            return []
        return config['chat_ids']
    except json.JSONDecodeError as e:
        print(f"错误：telegram.conf 解析失败 ({str(e)})，重置为空列表")
        with open(TELEGRAM_CONFIG, 'w') as f:
            json.dump({"chat_ids": []},
