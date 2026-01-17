#!/usr/bin/env python3
"""
DAT文件电话号码替换脚本 (Python版 - INI配置)
Reads configuration from config.ini
"""
import os
import sys
import csv
import configparser
from datetime import datetime

def load_config(config_file='config.ini'):
    """Load configuration from INI file"""
    config = configparser.ConfigParser()
    config.read(config_file, encoding='utf-8')
    
    settings = {
        'RecordSize': config.getint('Settings', 'RecordSize', fallback=1300),
        'HeaderMarker': config.getint('Settings', 'HeaderMarker', fallback=1),
        'DataMarker': config.getint('Settings', 'DataMarker', fallback=2),
        'MappingFile': config.get('Settings', 'MappingFile', fallback='mapping/mapping.csv'),
    }
    
    fields = []
    for section in config.sections():
        if section.startswith('Phone-'):
            field = {
                'name': config.get(section, 'Name', fallback=section),
                'start_byte': config.getint(section, 'StartByte'),
                'length': config.getint(section, 'Length'),
            }
            fields.append(field)
    
    return settings, fields

def main():
    filename = sys.argv[1] if len(sys.argv) > 1 else 'data.dat'
    config_file = sys.argv[2] if len(sys.argv) > 2 else 'config.ini'
    
    if not os.path.exists(config_file):
        print(f"Error: Config file {config_file} not found!")
        return 1
    
    settings, fields = load_config(config_file)
    
    RECORD_SIZE = settings['RecordSize']
    HEADER_MARKER = 0x30 + settings['HeaderMarker']
    DATA_MARKER = 0x30 + settings['DataMarker']
    
    input_file = f'in/{filename}'
    output_file = f'out/{filename}'
    mapping_path = settings['MappingFile']
    
    os.makedirs('out', exist_ok=True)
    os.makedirs('log', exist_ok=True)
    
    if not os.path.exists(input_file):
        print(f"Error: {input_file} not found!")
        return 1
    if not os.path.exists(mapping_path):
        print(f"Error: {mapping_path} not found!")
        return 1
    
    # Load mapping
    phone_mapping = {}
    with open(mapping_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) >= 2 and row[0].strip() and row[1].strip():
                phone_mapping[row[0].strip()] = row[1].strip()
    
    timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
    log_file = f'log/{filename.replace(".dat", "")}_{timestamp}.log'
    
    logs = []
    def log(msg):
        logs.append(msg)
        print(msg)
    
    log("╔══════════════════════════════════════════════════════════════╗")
    log("║  DAT Phone Replacer (BigEndianUnicode) - INI Config          ║")
    log("╚══════════════════════════════════════════════════════════════╝")
    log(f"Config:  {config_file}")
    log(f"Input:   {input_file}")
    log(f"Output:  {output_file}")
    log(f"Mapping: {mapping_path} ({len(phone_mapping)} rules)")
    log("")
    
    file_size = os.path.getsize(input_file)
    record_count = file_size // RECORD_SIZE
    log(f"File size: {file_size} bytes, Records: {record_count}, Fields: {len(fields)}")
    log("")
    log("─" * 64)
    
    modified_count = 0
    replaced_count = 0
    
    with open(input_file, 'rb') as f_in, open(output_file, 'wb') as f_out:
        for i in range(record_count):
            record = bytearray(f_in.read(RECORD_SIZE))
            record_num = i + 1
            first_byte = record[0]
            
            if first_byte == HEADER_MARKER:
                log(f"[#{record_num:4d}] HEADER - Skip")
            elif first_byte == DATA_MARKER:
                changes = []
                has_change = False
                
                for field in fields:
                    offset = field['start_byte'] - 1
                    byte_len = field['length'] * 2  # BigEndianUnicode
                    
                    phone_bytes = bytes(record[offset:offset+byte_len])
                    current_phone = phone_bytes.decode('utf-16-be', errors='replace')
                    
                    if current_phone in phone_mapping:
                        new_phone = phone_mapping[current_phone]
                        if len(new_phone) == field['length']:
                            new_bytes = new_phone.encode('utf-16-be')
                            record[offset:offset+byte_len] = new_bytes
                            changes.append(f"  {field['name']}: [{current_phone}] → [{new_phone}]")
                            has_change = True
                            replaced_count += 1
                        else:
                            changes.append(f"  {field['name']}: Length mismatch")
                    else:
                        changes.append(f"  {field['name']}: [{current_phone}] No match")
                
                if has_change:
                    log(f"[#{record_num:4d}] REPLACED")
                    for c in changes:
                        log(c)
                    modified_count += 1
            
            f_out.write(record)
    
    log("")
    log("─" * 64)
    log(f"Summary: {modified_count}/{record_count} records, {replaced_count} phones replaced")
    
    with open(log_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(logs))
    
    print(f"\n✓ Output: {output_file}")
    print(f"✓ Log: {log_file}")
    return 0

if __name__ == '__main__':
    sys.exit(main())
