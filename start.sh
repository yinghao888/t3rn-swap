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
pip3 install web3 python-telegram-bot --user
if [[ $? -ne 0 ]]; then
    echo "Python 依赖安装失败，尝试以全局模式安装..."
    sudo pip3 install web3 python-telegram-bot
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

# 检查 Node.js 和 npm
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    echo "未找到 Node.js 或 npm，尝试安装..."
    sudo apt-get update
    sudo apt-get install -y nodejs npm
    if [[ $? -ne 0 ]]; then
        echo "Node.js 和 npm 安装失败，请手动安装"
        exit 1
    fi
fi

# 检查 pm2
if ! command -v pm2 &> /dev/null; then
    echo "未找到 pm2，尝试安装..."
    sudo npm install -g pm2
    if [[ $? -ne 0 ]]; then
        echo "pm2 安装失败，请手动安装"
        exit 1
    fi
fi

# 下载 cross_chain.py 脚本
echo "下载 cross_chain.py 脚本..."
wget -O cross_chain.py https://raw.githubusercontent.com/yinghao888/t3rn-swap/main/cross_chain.py
if [[ $? -ne 0 ]]; then
    echo "下载 cross_chain.py 失败，请检查网络或仓库地址"
    exit 1
fi

sed -i 's/\r//' cross_chain.py
chmod +x cross_chain.py

# 使用 pm2 启动脚本
echo "使用 pm2 启动跨链脚本..."
pm2 start cross_chain.py --name cross-chain --interpreter python3
if [[ $? -ne 0 ]]; then
    echo "pm2 启动脚本失败，请检查 pm2 状态"
    exit 1
fi

# 保存 pm2 进程列表并设置开机自启
pm2 save
pm2 startup

echo "跨链脚本已通过 pm2 启动，进程名称为 cross-chain"
echo "你可以使用以下命令管理脚本："
echo "  查看状态：pm2 status"
echo "  查看日志：pm2 logs cross-chain"
echo "  停止脚本：pm2 stop cross-chain"
echo "  重启脚本：pm2 restart cross-chain"
