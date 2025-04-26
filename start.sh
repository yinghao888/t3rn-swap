#!/bin/bash

# 检查 Python 版本
PYTHON_MIN_VERSION="3.8"
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
if [[ -z "$PYTHON_VERSION" ]]; then
    echo "未找到 Python3，请安装 Python 3.8 或更高版本"
    exit 1
fi

if [[ "$(printf '%s\n' "$PYTHON_MIN_VERSION" "$PYTHON_VERSION" | sort -V | head -n1)" != "$PYTHON_MIN_VERSION" ]]; then
    echo "Python 版本 $PYTHON_VERSION 不满足最低要求 $PYTHON_MIN_VERSION"
    exit 1
fi

# 检查 pip
if ! command -v pip3 &> /dev/null; then
    echo "未找到 pip3，尝试安装..."
    sudo apt-get update
    sudo apt-get install -y python3-pip
fi

# 安装依赖
echo "检查并安装 Python 依赖..."
pip3 install web3 python-telegram-bot --user

# 下载并运行主脚本
echo "下载 t3rn-swap 脚本..."
wget -O cross_chain.py https://raw.githubusercontent.com/yinghao888/t3rn-swap/main/cross_chain.py
if [[ $? -ne 0 ]]; then
    echo "下载脚本失败，请检查仓库地址或网络"
    exit 1
fi

sed -i 's/\r//' cross_chain.py
chmod +x cross_chain.py
echo "启动跨链脚本..."
python3 cross_chain.py
