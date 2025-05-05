#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 与主程序相同的盐值，确保生成和验证使用相同算法
ACTIVATION_SALT="t3rn-swap-salt-2024"
UNIVERSAL_PREFIX="UNIVERSAL-KEY-"

# 生成通用激活码函数
generate_universal_license() {
    local key_id="$1"
    local days="$2"
    local expire_date=$(date -d "+$days days" +%Y%m%d)
    
    # 使用通用前缀+唯一ID作为机器ID替代
    local universal_id="${UNIVERSAL_PREFIX}${key_id}"
    
    local license_data="${universal_id}|${expire_date}|${ACTIVATION_SALT}"
    local license_code=$(echo -n "$license_data" | md5sum | awk '{print $1}')
    echo "${universal_id}|${license_code}|${expire_date}"
}

# 横幅
echo -e "${CYAN}=================================================="
echo "           通用激活码批量生成工具           "
echo "==================================================${NC}"

# 输入批次标识符
echo -e "${CYAN}请输入批次标识符(例如: BATCH001):${NC}"
read -p "> " batch_id

# 输入要生成的数量
echo -e "${CYAN}请输入要生成的激活码数量:${NC}"
read -p "> " count

# 检查数量是否有效
if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -le 0 ]; then
    echo -e "${RED}错误: 无效的数量，必须是正整数${NC}"
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

# 确认生成
echo -e "${CYAN}将生成 ${count} 个有效期为 ${days} 天的通用激活码，确认? (y/n)${NC}"
read -p "> " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo -e "${RED}已取消操作${NC}"
    exit 0
fi

# 创建输出目录
output_dir="licenses_${batch_id}_${days}days"
mkdir -p "$output_dir"

# 生成激活码
echo -e "${CYAN}正在生成激活码...${NC}"
output_file="${output_dir}/universal_licenses.csv"
echo "序号,激活码,过期日期" > "$output_file"

for ((i=1; i<=$count; i++)); do
    # 生成唯一ID
    key_id="${batch_id}-$(printf "%04d" $i)"
    
    # 生成激活码
    license_info=$(generate_universal_license "$key_id" "$days")
    IFS='|' read -r universal_id license_code expire_date <<< "$license_info"
    
    # 保存到CSV文件
    formatted_expire=$(date -d "${expire_date}" +"%Y-%m-%d")
    echo "$i,${license_code}|${expire_date},${formatted_expire}" >> "$output_file"
    
    # 显示进度
    if [ $((i % 10)) -eq 0 ] || [ $i -eq $count ]; then
        echo -e "${GREEN}已生成 $i/$count 个激活码${NC}"
    fi
done

# 生成说明文件
cat > "${output_dir}/README.txt" << EOF
通用激活码说明
=======================
批次标识: $batch_id
有效期: $days 天
生成数量: $count 个
生成日期: $(date +"%Y-%m-%d %H:%M:%S")

激活码格式: HASH值|过期日期
示例: 7a8b9c0d1e2f3g4h5i6j7k8l9m0n1o2p|20241231

使用方法:
1. 运行跨链脚本
2. 选择"激活码管理"
3. 选择"输入新激活码"
4. 输入完整的激活码(包含竖线和日期)

注意事项:
- 每个激活码仅能在一台设备上使用
- 到期后需要输入新的激活码继续使用
- 请妥善保管激活码，避免泄露
EOF

echo -e "${GREEN}批量生成完成!${NC}"
echo -e "${CYAN}共生成了 ${count} 个通用激活码${NC}"
echo -e "${CYAN}激活码列表保存在: ${output_file}${NC}"
echo -e "${CYAN}使用说明保存在: ${output_dir}/README.txt${NC}" 