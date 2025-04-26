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

# 安装 Python 依赖
echo "检查并安装 Python 依赖..."
pip3 install web3 python-telegram-bot urllib3==1.26.6 chardet==4.0.0 --user
if [[ $? -ne 0 ]]; then
    echo "Python 依赖安装失败，尝试以全局模式安装..."
    sudo pip3 install web3 python-telegram-bot urllib3==1.26.6 chardet==4.0.0
    if [[ $? -ne 0 ]]; then
        echo "Python 依赖安装失败，请检查网络或 pip 配置"
        exit 1
    fi
fi

# 检查 Python 依赖是否安装成功
python3 -c "import telegram" 2>/dev/null
if [[ $? -ne 0 ]]; then
    echo "python-telegram-bot 模块未正确安装，请检查"
    exit 1
fi
python3 -c "import web3" 2>/dev/null
if [[ $? -ne 0 ]]; then
    echo "web3 模块未正确安装，请检查"
    exit 1
fi

# 检查 screen
if ! command -v screen &> /dev/null; then
    echo "未找到 screen，尝试安装..."
    sudo apt-get update
    sudo apt-get install -y screen
    if [[ $? -ne 0 ]]; then
        echo "screen 安装失败，请手动安装"
        exit 1
    fi
fi

# 下载 menu.py 和 worker.py 脚本
echo "下载 menu.py 脚本..."
wget -O menu.py https://raw.githubusercontent.com/yinghao888/t3rn-swap/main/menu.py
if [[ $? -ne 0 ]]; then
    echo "下载 menu.py 失败，请检查网络或仓库地址"
    exit 1
fi

echo "下载 worker.py 脚本..."
wget -O worker.py https://raw.githubusercontent.com/yinghao888/t3rn-swap/main/worker.py
if [[ $? -ne 0 ]]; then
    echo "下载 worker.py 失败，请检查网络或仓库地址"
    exit 1
fi

sed -i 's/\r//' menu.py
sed -i 's/\r//' worker.py
chmod +x menu.py worker.py

# 运行 menu.py 进行交互
echo "运行 menu.py 进行交互..."
python3 menu.py
