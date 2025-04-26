#!/bin/bash

# 检查 Python 版本
PYTHON_MIN_VERSION="3.8"
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
if [[ -z "$PYTHON_VERSION" ]]; then
    echo "未找到 Python3，请安装 Python 3.8 或更高版本"
    exit 1
fi

# 比较版本
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

# 检查主脚本是否存在
if [[ ! -f "cross_chain.py" ]]; then
    echo "未找到 cross_chain.py 脚本"
    exit 1
fi

# 启动主脚本
echo "启动跨链脚本..."
python3 cross_chain.py
