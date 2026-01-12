#!/usr/bin/env python3
"""
DAT文件电话号码替换脚本 (Python - FileStream版)
功能：根据CSV映射表替换DAT文件中的电话号码
"""
import os
import sys
import csv
from datetime import datetime

# ==================== 基本配置 ====================
FILE_NAME = sys.argv[1] if len(sys.argv) > 1 else "data.dat"
MAPPING_FILE = sys.argv[2] if len(sys.argv) > 2 else "mapping.csv"

IN_FOLDER = "in"
OUT_FOLDER = "out"
LOG_FOLDER = "log"
MAPPING_FOLDER = "mapping"

RECORD_SIZE = 1300
HEADER_MARKER = ord('1')
DATA_MARKER = ord('2')

# ==================== 电话号码字段配置 ====================
PHONE_FIELDS = [
    {"name": "Phone-1", "start_byte": 100, "length": 10},
    {"name": "Phone-2", "start_byte": 200, "length": 10},
    # 添加更多字段...
]

# ==================== 脚本逻辑 ====================

timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
input_file = os.path.join(IN_FOLDER, FILE_NAME)
output_file = os.path.join(OUT_FOLDER, FILE_NAME)
mapping_path = os.path.join(MAPPING_FOLDER, MAPPING_FILE)
log_file = os.path.join(LOG_FOLDER, f"{FILE_NAME.replace('.dat','')}{timestamp}.log")

for folder in [OUT_FOLDER, LOG_FOLDER]:
    os.makedirs(folder, exist_ok=True)

if not os.path.exists(input_file):
    print(f"错误: DAT文件 '{input_file}' 不存在！")
    sys.exit(1)
if not os.path.exists(mapping_path):
    print(f"错误: 映射文件 '{mapping_path}' 不存在！")
    sys.exit(1)

# ==================== 加载CSV映射表 ====================

phone_mapping = {}
with open(mapping_path, 'r', encoding='utf-8') as f:
    reader = csv.reader(f)
    for row in reader:
        if len(row) >= 2 and row[0].strip() and row[1].strip():
            phone_mapping[row[0].strip()] = row[1].strip()

log_lines = []
def log(msg):
    log_lines.append(msg)
    print(msg)

log("╔══════════════════════════════════════════════════════════════╗")
log("║  DAT Phone Replacer (Python - FileStream)                    ║")
log("╠══════════════════════════════════════════════════════════════╣")
log(f"║  时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S'):50}║")
log(f"║  输入:  {input_file:50}║")
log(f"║  输出: {output_file:50}║")
log(f"║  映射: {mapping_path:50}║")
log("╚══════════════════════════════════════════════════════════════╝")
log("")
log(f"已加载 {len(phone_mapping)} 条电话号码映射规则")
log("")

file_size = os.path.getsize(input_file)
record_count = file_size // RECORD_SIZE

log(f"文件大小: {file_size} 字节")
log(f"记录总数: {record_count} | 字段数量: {len(PHONE_FIELDS)}")
log("─" * 64)
log("")

modified_count = 0
replaced_phone_count = 0

with open(input_file, "rb") as fin, open(output_file, "wb") as fout:
    for i in range(record_count):
        record = bytearray(fin.read(RECORD_SIZE))
        
        if len(record) != RECORD_SIZE:
            log(f"[#{i+1:4}] 错误 - 读取字节不足: {len(record)} / {RECORD_SIZE}")
            fout.write(record)
            continue
        
        record_num = i + 1
        first_byte = record[0]
        
        if first_byte == HEADER_MARKER:
            log(f"[#{record_num:4}] HEADER - 已跳过")
        elif first_byte == DATA_MARKER:
            changes = []
            has_change = False
            
            for field in PHONE_FIELDS:
                field_offset = field["start_byte"] - 1
                current_phone = record[field_offset:field_offset + field["length"]].decode("ascii")
                
                if current_phone in phone_mapping:
                    new_phone = phone_mapping[current_phone]
                    
                    if len(new_phone) == field["length"]:
                        record[field_offset:field_offset + field["length"]] = new_phone.encode("ascii")
                        changes.append(f"  {field['name']}: [{current_phone}] → [{new_phone}]")
                        has_change = True
                        replaced_phone_count += 1
                    else:
                        changes.append(f"  {field['name']}: 长度不匹配 (期望{field['length']}, 实际{len(new_phone)})")
                else:
                    changes.append(f"  {field['name']}: [{current_phone}] 无匹配")
            
            if has_change:
                log(f"[#{record_num:4}] REPLACED")
                modified_count += 1
            else:
                log(f"[#{record_num:4}] NO MATCH")
            for c in changes:
                log(c)
        
        fout.write(record)

log("")
log("─" * 64)
log("处理摘要:")
log(f"  修改记录数: {modified_count} / {record_count}")
log(f"  替换号码数: {replaced_phone_count}")
log("─" * 64)

with open(log_file, "w", encoding="utf-8") as f:
    f.write("\n".join(log_lines))

print(f"\n✓ 输出文件: {output_file}")
print(f"✓ 日志文件: {log_file}")
