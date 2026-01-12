#!/usr/bin/env python3
"""为dat-phone-replacer生成示例文件"""
import os

RECORD_SIZE = 1300

def create_record(first_byte, phone1, phone2):
    record = bytearray(b' ' * RECORD_SIZE)
    record[0] = first_byte
    record[99:109] = phone1.encode()
    record[199:209] = phone2.encode()
    return record

data = bytearray()
data.extend(create_record(ord('1'), "0000000000", "0000000000"))  # Header
data.extend(create_record(ord('2'), "1381234567", "1391234567"))
data.extend(create_record(ord('2'), "1382345678", "1392345678"))
data.extend(create_record(ord('2'), "1383456789", "1393456789"))

with open("in/sample.dat", "wb") as f:
    f.write(data)
print(f"Created: in/sample.dat ({len(data)} bytes)")
