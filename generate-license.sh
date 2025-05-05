#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 与主程序相同的盐值，确保生成和验证使用相同算法
ACTIVATION_SALT="t3rn-swap-salt-2024"

# 生成激活码函数
generate_license_code() {
    local machine_id="$1"
    local days="$2"
    local expire_date=$(date -d "+$days days" +%Y%m%d)
    local license_data="${machine_id}|${expire_date}|${ACTIVATION_SALT}"
    local license_code=$(echo -n "$license_data" | md5sum | awk '{print $1}')
    echo "${license_code}|${expire_date}"
}

# 横幅
echo -e "${CYAN}=================================================="
echo "             激活码生成工具             "
echo "==================================================${NC}"

# 输入机器ID
echo -e "${CYAN}请输入客户的机器ID:${NC}"
read -p "> " machine_id

# 检查机器ID格式
if [[ ! "$machine_id" =~ ^[0-9a-f]{32}$ ]]; then
    echo -e "${RED}错误: 无效的机器ID格式，应为32位十六进制字符串${NC}"
    exit 1
fi

# 输入有效期天数
echo -e "${CYAN}请输入激活码有效期天数:${NC}"
read -p "> " days

# 检查天数是否有效
if ! [[ "$days" =~ ^[0-9]+$ ]] || [ "$days" -le 0 ]; then
    echo -e "${RED}错误: 无效的天数，必须是正整数${NC}"
    exit 1
fi

# 生成激活码
license_code=$(generate_license_code "$machine_id" "$days")

# 提取过期日期并格式化
IFS='|' read -r code_part expire_date <<< "$license_code"
formatted_expire=$(date -d "${expire_date}" +"%Y年%m月%d日")

# 显示结果
echo -e "${GREEN}已成功生成激活码:${NC}"
echo -e "${CYAN}机器ID: ${NC}${machine_id}"
echo -e "${CYAN}有效期: ${NC}${days}天 (至${formatted_expire})"
echo -e "${CYAN}激活码: ${NC}${license_code}"
echo ""
echo -e "${RED}请妥善保管激活码，不要泄露给无关人员！${NC}"

# 保存到文件
filename="license_${machine_id}_${days}days.txt"
echo "机器ID: ${machine_id}" > "$filename"
echo "有效期: ${days}天 (至${formatted_expire})" >> "$filename"
echo "激活码: ${license_code}" >> "$filename"
echo "" >> "$filename"
echo "已保存激活码信息到文件: $filename" 