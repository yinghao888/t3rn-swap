```python
from web3 import Web3
import time
from typing import List, Dict
import logging
from concurrent.futures import ThreadPoolExecutor
import os
import json
import asyncio
from cryptography.fernet import Fernet
from telegram import Bot

# === ANSI 颜色代码 ===
LIGHT_BLUE = "\033[96m"
LIGHT_RED = "\033[95m"
RESET = "\033[0m"

# === 配置日志 ===
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger()

# === 加密配置 ===
ENCRYPTION_KEY = Fernet.generate_key()  # 请妥善保存此密钥
CIPHER = Fernet(ENCRYPTION_KEY)
POINTS_JSON = "points.json"

# === Telegram 配置 ===
TELEGRAM_TOKEN = "8070858648:AAGfrK1u0IaiXjr4f8TRbUDD92uBGTXdt38"
TELEGRAM_CONFIG = "telegram.conf"

# 从 config.json 加载配置
try:
    with open("config.json", "r") as f:
        config = json.load(f)
except FileNotFoundError:
    logger.error("config.json 文件不存在")
    exit(1)
REQUEST_INTERVAL = config["REQUEST_INTERVAL"]
AMOUNT_ETH = config["AMOUNT_ETH"]
UNI_TO_ARB_DATA_TEMPLATE = config["UNI_TO_ARB_DATA_TEMPLATE"]
ARB_TO_UNI_DATA_TEMPLATE = config["ARB_TO_UNI_DATA_TEMPLATE"]

# 从 rpc_config.json 加载 RPC 配置
try:
    with open("rpc_config.json", "r") as f:
        rpc_config = json.load(f)
except FileNotFoundError:
    logger.error("rpc_config.json 文件不存在")
    exit(1)
ARB_RPC_URLS = rpc_config["ARB_RPC_URLS"]
UNI_RPC_URLS = rpc_config["UNI_RPC_URLS"]

# 从 points.json 加载点数（加密）
def check_points(address: str) -> int:
    try:
        if not os.path.exists(POINTS_JSON):
            return 0
        with open(POINTS_JSON, "rb") as f:
            encrypted_data = f.read()
        decrypted_data = CIPHER.decrypt(encrypted_data)
        points = json.loads(decrypted_data.decode())
        return points.get(address, 0)
    except Exception as e:
        logger.error(f"读取 points.json 失败: {e}")
        return 0

def deduct_points(address: str) -> bool:
    try:
        points = {}
        if os.path.exists(POINTS_JSON):
            with open(POINTS_JSON, "rb") as f:
                encrypted_data = f.read()
            decrypted_data = CIPHER.decrypt(encrypted_data)
            points = json.loads(decrypted_data.decode())
        current_points = points.get(address, 0)
        if current_points < 1:
            logger.warning
