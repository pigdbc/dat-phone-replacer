# DAT Phone Replacer / DAT电话号码替换工具

根据CSV映射表批量替换定长记录DAT文件中电话号码的工具。支持 BigEndianUnicode (UTF-16BE) 编码。

CSVマッピングテーブルに基づいて固定長レコードDATファイル内の電話番号を一括置換するツール。

---

## 📁 文件结构 / File Structure

```
dat-phone-replacer/
├── in/                                ← 输入文件夹 (放置原始DAT文件)
├── out/                               ← 输出文件夹 (自动生成)
├── log/                               ← 日志文件夹 (自动生成)
├── mapping/                           ← 映射文件夹 (放置CSV映射表)
│   └── mapping.csv
├── config.ini                         ← 配置文件
├── replace_phone.ps1                 ← PowerShell脚本
└── README.md
```

---

## 🚀 快速开始 / Quick Start

### PowerShell (Windows)

```powershell
.\replace_phone.ps1 -FileName "data.dat"
```

---

## ⚙️ 配置文件说明 / Configuration

规则配置已从代码中分离，统一使用 `config.ini` 文件：

```ini
[Settings]
RecordSize = 1300           # 每条记录的字符数
HeaderMarker = 1            # 头部记录标识符
DataMarker = 2              # 数据记录标识符
MappingFile = mapping/mapping.csv

[Phone-1]
Name = Phone-1
StartByte = 100             # 起始字符位置 (1-indexed)
Length = 10                 # 电话号码长度(字符数)

[Phone-2]
Name = Phone-2
StartByte = 200
Length = 10
```

---

## 📄 CSV映射文件格式 / CSV Format

CSV文件放在 `mapping/` 文件夹中：

```csv
1381234567,1991234567
1391234567,1891234567
```

**注意：** 新旧电话号码长度必须与字段配置一致（UTF-16BE 每字符 2 字节）

---

## 📝 运行示例

```
╔══════════════════════════════════════════════════════════════╗
║  DAT Phone Replacer (BigEndianUnicode) - INI Config          ║
╚══════════════════════════════════════════════════════════════╝
Config:  config.ini
Input:   in/data.dat
Mapping: mapping/mapping.csv (5 rules)

[#   2] REPLACED
  Phone-1: [1381234567] → [1991234567]
[#   3] REPLACED
  Phone-1: [1382345678] → [1992345678]

Summary: 3/4 records, 5 phones replaced
```

---

## 📌 技术特点 / Features

- ✅ **INI配置文件** - 规则配置与代码分离
- ✅ **BigEndianUnicode** - 支持 UTF-16BE 编码
- ✅ **哈希表查找** - O(1) 时间复杂度
- ✅ **流式读写** - 支持处理超大文件
- ✅ **多语言支持** - 中文、日本語配置文件

---

## 📄 License

MIT License
