# DAT Phone Replacer / DAT电话号码替换工具

A tool for batch replacing phone numbers in fixed-length record DAT files based on a CSV mapping table.

根据CSV映射表批量替换定长记录DAT文件中电话号码的工具。

CSVマッピングテーブルに基づいて固定長レコードDATファイル内の電話番号を一括置換するツール。

---

## 📁 文件结构 / File Structure

```
dat-phone-replacer/
├── in/                                ← 输入文件夹 (放置原始DAT文件)
├── out/                               ← 输出文件夹 (自动生成)
├── log/                               ← 日志文件夹 (自动生成)
├── mapping/                           ← 映射文件夹 (放置CSV映射表)
│   └── mapping.csv                    ← CSV映射文件
├── replace_phone_中文版.ps1           ← PowerShell脚本 (中文界面)
├── replace_phone_日文版.ps1           ← PowerShell脚本 (日本語)
├── replace_phone_中文版_详细注释.ps1  ← 带详细注释的学习版
├── replace_phone.py                   ← Python版脚本
└── README.md
```

---

## 📄 CSV映射文件格式 / CSV Format

CSV文件放在 `mapping/` 文件夹中，格式为：

```csv
OldPhone,NewPhone
1381234567,1391234567
1382345678,1392345678
1383456789,1393456789
```

**注意：**
- 每行一条映射规则
- 第一列是原电话号码，第二列是新电话号码
- 电话号码长度必须与字段配置一致（默认10位）
- 可以没有标题行

---

## 🚀 快速开始 / Quick Start

### PowerShell (Windows)

```powershell
# 1. 将DAT文件放入 in/ 文件夹
# 2. 将CSV映射文件放入 mapping/ 文件夹
# 3. 运行脚本
.\replace_phone_中文版.ps1 -FileName "yourfile.dat" -MappingFile "mapping.csv"

# 或使用默认文件名
.\replace_phone_中文版.ps1
```

### Python (跨平台)

```bash
# 使用方法
python3 replace_phone.py [dat文件名] [csv映射文件名]

# 示例
python3 replace_phone.py data.dat mapping.csv
```

---

## ⚙️ 配置说明 / Configuration

### 基本配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `$RecordSize` | `1300` | 每条记录的字节数 |
| `$HeaderMarker` | `0x31` ('1') | Header记录标识符 |
| `$DataMarker` | `0x32` ('2') | 数据记录标识符 |

### 电话号码字段配置

在脚本中修改 `$PhoneFields` 数组来配置电话号码的位置：

```powershell
$PhoneFields = @(
    @{
        Name       = "Phone-1"     # 字段名称
        StartByte  = 100           # 起始位置 (1-indexed)
        Length     = 10            # 电话号码长度
    },
    @{
        Name       = "Phone-2"
        StartByte  = 200
        Length     = 10
    }
    # 添加更多字段...
)
```

---

## 📝 输出日志示例 / Log Example

```
╔══════════════════════════════════════════════════════════════╗
║  DAT Phone Replacer (FileStream) - 中文版                    ║
╠══════════════════════════════════════════════════════════════╣
║  时间: 2026-01-12 21:45:00                                   ║
║  输入:  in/data.dat                                          ║
║  输出: out/data.dat                                          ║
║  映射: mapping/mapping.csv                                   ║
╚══════════════════════════════════════════════════════════════╝

已加载 100 条电话号码映射规则

Records: 5 | Fields: 2
────────────────────────────────────────────────────────────────

[#   1] HEADER - 已跳过
[#   2] REPLACED
  Phone-1: [1381234567] → [1391234567]
  Phone-2: [1382345678] 无匹配
[#   3] NO MATCH
  Phone-1: [1399999999] 无匹配
  Phone-2: [1388888888] 无匹配

────────────────────────────────────────────────────────────────
处理摘要:
  修改记录数: 1 / 5
  替换号码数: 1
────────────────────────────────────────────────────────────────
```

---

## 📌 技术特点 / Features

- ✅ **哈希表查找** - O(1)时间复杂度，支持大量映射规则
- ✅ **FileStream流式读写** - 支持处理超大文件，内存占用低
- ✅ **精确字节控制** - 每次精确读取指定字节数
- ✅ **长度验证** - 自动检测新旧电话号码长度是否匹配
- ✅ **详细日志** - 记录每条记录的替换详情
- ✅ **多语言支持** - 中文、日文界面可选

---

## 📄 License

MIT License
