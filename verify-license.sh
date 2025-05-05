#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 与主程序相同的盐值，确保生成和验证使用相同算法
ACTIVATION_SALT="t3rn-swap-salt-2024"

# 横幅
echo -e "${CYAN}=================================================="
echo "             激活码验证工具             "
echo "==================================================${NC}"

# 输入激活码
echo -e "${CYAN}请输入要验证的激活码:${NC}"
read -p "> " license_code

# 检查激活码格式
if [[ ! "$license_code" == *"|"* ]]; then
    echo -e "${RED}错误: 无效的激活码格式，缺少分隔符${NC}"
    exit 1
fi

# 从激活码中提取过期日期和校验码
IFS='|' read -r code_part expire_date <<< "$license_code"

# 验证激活码格式
if [[ ! "$code_part" =~ ^[0-9a-f]{32}$ ]]; then
    echo -e "${RED}错误: 无效的激活码哈希部分${NC}"
    exit 1
fi

if [[ ! "$expire_date" =~ ^[0-9]{8}$ ]]; then
    echo -e "${RED}错误: 无效的过期日期格式${NC}"
    exit 1
fi

# 检查是否过期
current_date=$(date +%Y%m%d)
formatted_expire=$(date -d "${expire_date}" +"%Y年%m月%d日" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}错误: 无法解析过期日期${NC}"
    exit 1
fi

if [ "$current_date" -gt "$expire_date" ]; then
    echo -e "${RED}激活码已过期!${NC}"
    echo -e "${CYAN}过期日期: ${formatted_expire}${NC}"
    exit 2
fi

# 计算剩余天数
days_remaining=$(( ( $(date -d "${expire_date}" +%s) - $(date +%s) ) / 86400 ))

# 显示验证结果
echo -e "${GREEN}激活码格式验证通过!${NC}"
echo -e "${CYAN}过期日期: ${formatted_expire}${NC}"
echo -e "${CYAN}剩余天数: ${days_remaining} 天${NC}"

# 询问是否要测试安装在特定机器上
echo -e "${CYAN}是否要测试此激活码在特定机器ID上的有效性? (y/n)${NC}"
read -p "> " test_machine
if [ "$test_machine" = "y" ] || [ "$test_machine" = "Y" ]; then
    echo -e "${CYAN}请输入机器ID:${NC}"
    read -p "> " machine_id
    
    # 验证机器ID格式
    if [[ ! "$machine_id" =~ ^[0-9a-f]{32}$ ]]; then
        echo -e "${RED}错误: 无效的机器ID格式，应为32位十六进制字符串${NC}"
        exit 1
    fi
    
    # 使用相同算法计算预期校验码
    license_data="${machine_id}|${expire_date}|${ACTIVATION_SALT}"
    calculated_code=$(echo -n "$license_data" | md5sum | awk '{print $1}')
    
    # 检查是否匹配
    if [ "$calculated_code" = "$code_part" ]; then
        echo -e "${GREEN}在指定机器上验证成功!${NC}"
        echo -e "${CYAN}此激活码可用于此机器ID${NC}"
    else
        echo -e "${RED}在指定机器上验证失败!${NC}"
        echo -e "${CYAN}此激活码不适用于此机器ID${NC}"
        echo -e "${CYAN}预期激活码应为: ${calculated_code}|${expire_date}${NC}"
    fi
fi

exit 0 