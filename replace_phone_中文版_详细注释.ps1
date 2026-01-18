# ============================================
# DAT文件电话号码替换脚本 (中文版 - 详细注释版 - BigEndianUnicode)
# 功能说明：
#   1. 从config.ini读取配置（记录大小、字段定义等）
#   2. 从mapping文件夹读取CSV映射表（旧电话→新电话）
#   3. 从in文件夹读取DAT文件
#   4. 逐条记录扫描，将匹配的电话号码替换为新号码
#   5. 将修改后的文件写入out文件夹
#   6. 生成详细的处理日志到log文件夹
# ============================================

# ==================== 脚本参数定义 ====================
# -FileName: DAT文件名（不含路径）
# -MappingFile: CSV映射文件名（不含路径）
param(
    [string]$FileName = "data.dat",      # 要处理的DAT文件，默认data.dat
    [string]$MappingFile = "mapping.csv"  # 映射表文件，默认mapping.csv
)

# ==================== 文件夹配置 ====================
# 这些变量定义了各类文件的存放位置
$InFolder      = "in"       # 输入文件夹：存放原始DAT文件
$OutFolder     = "out"      # 输出文件夹：存放修改后的DAT文件
$LogFolder     = "log"      # 日志文件夹：存放处理日志
$MappingFolder = "mapping"  # 映射文件夹：存放CSV映射表

# ==================== 配置文件加载 ====================
# 使用config.ini作为配置文件
$ConfigFile = "config.ini"

# INI文件解析函数
# 将INI格式的配置文件解析为嵌套的哈希表结构
# 返回格式：@{ "Section1" = @{ "Key1" = "Value1"; "Key2" = "Value2" }; "Section2" = ... }
function Parse-IniFile {
    param([string]$FilePath)
    $ini = @{}                              # 初始化空哈希表
    $section = "Global"                      # 默认section名称
    if (-not (Test-Path $FilePath)) { return $ini }  # 文件不存在则返回空哈希表
    
    # 逐行读取文件
    Get-Content $FilePath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()                    # 去除首尾空格
        # 跳过空行和注释行（以;或#开头）
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(";") -or $line.StartsWith("#")) { return }
        # 匹配section标题，如 [Settings]
        if ($line -match "^\[(.*)\\]$") {
            $section = $matches[1]
            $ini[$section] = @{}
        # 匹配键值对，如 RecordSize = 1300
        } elseif ($line -match "^(.*?)=(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if (-not $ini.ContainsKey($section)) { $ini[$section] = @{} }
            $ini[$section][$key] = $value
        }
    }
    return $ini
}

# 解析配置文件
$ConfigData = Parse-IniFile -FilePath $ConfigFile

# ==================== 记录配置 ====================
# 这些常量定义了DAT文件的结构特征
# 先设置默认值，然后从INI文件覆盖

$RecordSize   = 1300       # 每条记录的固定字节数（默认值）
$HeaderMarker = 0x31       # Header记录的首字节标识符（ASCII字符'1'）
$DataMarker   = 0x32       # 数据记录的首字节标识符（ASCII字符'2'）

# 从INI文件加载设置（如果存在）
if ($ConfigData.ContainsKey("Settings")) {
    # 记录大小
    if ($ConfigData["Settings"]["RecordSize"]) { 
        $RecordSize = [int]$ConfigData["Settings"]["RecordSize"] 
    }
    # HeaderMarker: INI中存的是数字1，需要转换为ASCII字符'1'的字节值0x31
    if ($ConfigData["Settings"]["HeaderMarker"]) { 
        $HeaderMarker = [int]$ConfigData["Settings"]["HeaderMarker"] + 0x30 
    }
    # DataMarker: INI中存的是数字2，需要转换为ASCII字符'2'的字节值0x32
    if ($ConfigData["Settings"]["DataMarker"]) { 
        $DataMarker = [int]$ConfigData["Settings"]["DataMarker"] + 0x30 
    }
    # 映射文件路径
    if ($ConfigData["Settings"]["MappingFile"]) { 
        $MappingFile = $ConfigData["Settings"]["MappingFile"] 
    }
}

# ==================== 电话号码字段配置 (从INI加载) ====================
# 动态从INI文件加载所有以"Phone-"开头的section作为字段配置
# 每个字段包含：Name（字段名）、StartByte（起始字节位置）、CharLength（字符数）
$PhoneFields = @()
foreach ($key in $ConfigData.Keys) {
    if ($key -like "Phone-*") {
        $PhoneFields += @{
            Name       = $ConfigData[$key]["Name"]          # 字段名称（用于日志显示）
            StartByte  = [int]$ConfigData[$key]["StartByte"]  # 起始位置（从1开始计数）
            CharLength = [int]$ConfigData[$key]["Length"]     # 电话号码字符数
        }
    }
}

# 如果INI中没有定义字段，使用默认值
if ($PhoneFields.Count -eq 0) {
    $PhoneFields = @(
        @{ Name = "Phone-1"; StartByte = 100; CharLength = 10 },
        @{ Name = "Phone-2"; StartByte = 200; CharLength = 10 }
    )
}

# ==================== 脚本初始化 ====================

# 生成时间戳，用于日志文件名
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# 构建完整的文件路径
$InputFile   = Join-Path $InFolder $FileName                                    # 输入DAT文件路径
$OutputFile  = Join-Path $OutFolder $FileName                                   # 输出DAT文件路径
$MappingPath = Join-Path $MappingFolder $MappingFile                            # CSV映射文件路径
$LogFile     = Join-Path $LogFolder "$($FileName -replace '\.dat$','')_$timestamp.log"  # 日志文件路径

# 创建必要的文件夹（输出和日志文件夹）
foreach ($folder in @($OutFolder, $LogFolder)) {
    if (-not (Test-Path $folder)) {                           # 检查文件夹是否存在
        New-Item -ItemType Directory -Path $folder -Force | Out-Null  # 不存在则创建
    }
}

# 检查必需的文件是否存在
if (-not (Test-Path $InputFile)) {
    Write-Host "错误: DAT文件 '$InputFile' 不存在！" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $MappingPath)) {
    Write-Host "错误: 映射文件 '$MappingPath' 不存在！" -ForegroundColor Red
    exit 1
}

# ==================== 加载CSV映射表 ====================

# 创建一个哈希表（字典）用于存储电话号码映射
# 哈希表的查找时间复杂度是O(1)，非常适合大量数据的快速匹配
$phoneMapping = @{}

# 使用Import-Csv读取CSV文件
# -Header参数指定列名（如果CSV没有标题行）
# CSV格式示例：
#   1381234567,1391234567
#   1382345678,1392345678
$csvData = Import-Csv -Path $MappingPath -Header "OldPhone","NewPhone"

# 遍历每一行，将旧号码→新号码的映射存入哈希表
foreach ($row in $csvData) {
    # 跳过空行
    if ($row.OldPhone -and $row.NewPhone) {
        # Trim()去除首尾空格，确保匹配准确
        $phoneMapping[$row.OldPhone.Trim()] = $row.NewPhone.Trim()
    }
}

# ==================== 日志函数定义 ====================

# 创建StringBuilder用于收集日志（比字符串拼接效率高）
$logContent = [System.Text.StringBuilder]::new()

# 日志函数：同时输出到控制台和收集到StringBuilder
function Log($msg) {
    [void]$logContent.AppendLine($msg)  # 追加到StringBuilder
    Write-Host $msg                      # 输出到控制台
}

# ==================== 显示脚本信息头 ====================

Log "╔══════════════════════════════════════════════════════════════╗"
Log "║  DAT Phone Replacer - 中文详细注释版                         ║"
Log "╠══════════════════════════════════════════════════════════════╣"
Log "║  时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                               ║"
Log "║  配置: $($ConfigFile.PadRight(50))║"
Log "║  输入: $($InputFile.PadRight(50))║"
Log "║  输出: $($OutputFile.PadRight(50))║"
Log "║  映射: $($MappingPath.PadRight(50))║"
Log "╚══════════════════════════════════════════════════════════════╝"
Log ""
Log "已加载 $($phoneMapping.Count) 条电话号码映射规则"
Log "已加载 $($PhoneFields.Count) 个电话号码字段配置"
Log ""

# ==================== 获取文件信息 ====================

$fileInfo = Get-Item $InputFile
$fileLength = $fileInfo.Length
$recordCount = [Math]::Floor($fileLength / $RecordSize)  # 计算记录总数

Log "文件大小: $fileLength 字节"
Log "记录大小: $RecordSize 字节"
Log "记录总数: $recordCount | 字段数量: $($PhoneFields.Count)"
Log ("─" * 64)
Log ""

# ==================== 初始化计数器和缓冲区 ====================

$modifiedCount = 0           # 已修改的记录计数
$replacedPhoneCount = 0      # 已替换的电话号码计数
$recordBuffer = New-Object byte[] $RecordSize  # 记录缓冲区

# ==================== 打开文件流 ====================

# 使用FileStream进行流式读写
# 优点：内存占用低，支持处理超大文件
$inputStream = [System.IO.File]::OpenRead($InputFile)
$outputStream = [System.IO.File]::Create($OutputFile)

# ==================== 主处理循环 ====================

try {
    # 遍历每一条记录
    for ($i = 0; $i -lt $recordCount; $i++) {
        
        # 从输入流读取一条完整记录（精确读取$RecordSize字节）
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSize)
        
        # 检查是否读取了完整的记录
        if ($bytesRead -ne $RecordSize) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] 错误 - 读取字节不足: $bytesRead / $RecordSize"
            continue
        }
        
        $recordNum = $i + 1           # 记录序号（从1开始）
        $firstByte = $recordBuffer[0]  # 首字节（标识符）
        
        # 根据首字节判断记录类型
        if ($firstByte -eq $HeaderMarker) {
            # 首字节是Header标记，这是Header记录，跳过
            Log "[#$($recordNum.ToString().PadLeft(4))] HEADER - 已跳过"
        }
        elseif ($firstByte -eq $DataMarker) {
            # 首字节是Data标记，这是数据记录，需要处理
            
            $changes = @()        # 存储本条记录的修改详情
            $hasChange = $false   # 标记本条记录是否有修改
            
            # 遍历每个电话号码字段
            foreach ($field in $PhoneFields) {
                # 计算字段在记录中的偏移量（StartByte是1-indexed）
                $fieldOffset = $field.StartByte - 1
                
                # 计算字节长度（BigEndianUnicode每个字符占2字节）
                $byteLen = $field.CharLength * 2
                
                # 从缓冲区读取当前电话号码
                $phoneBytes = New-Object byte[] $byteLen
                [Array]::Copy($recordBuffer, $fieldOffset, $phoneBytes, 0, $byteLen)
                $currentPhone = [System.Text.Encoding]::BigEndianUnicode.GetString($phoneBytes)
                
                # 检查当前电话号码是否在映射表中
                if ($phoneMapping.ContainsKey($currentPhone)) {
                    # 找到匹配，获取新电话号码
                    $newPhone = $phoneMapping[$currentPhone]
                    
                    # 验证新电话号码长度是否匹配
                    if ($newPhone.Length -eq $field.CharLength) {
                        # 将新电话号码转换为字节数组（BigEndianUnicode）
                        $newPhoneBytes = [System.Text.Encoding]::BigEndianUnicode.GetBytes($newPhone)
                        
                        # 将新电话号码写入记录缓冲区
                        [Array]::Copy($newPhoneBytes, 0, $recordBuffer, $fieldOffset, $byteLen)
                        
                        $changes += "  $($field.Name): [$currentPhone] → [$newPhone]"
                        $hasChange = $true
                        $replacedPhoneCount++  # 增加替换计数
                    } else {
                        # 长度不匹配，记录警告
                        $changes += "  $($field.Name): 长度不匹配 (期望$($field.CharLength), 实际$($newPhone.Length))"
                    }
                } else {
                    # 未找到匹配
                    $changes += "  $($field.Name): [$currentPhone] 无匹配"
                }
            }
            
            # 输出本条记录的处理结果
            if ($hasChange) {
                Log "[#$($recordNum.ToString().PadLeft(4))] REPLACED"
                $modifiedCount++
            } else {
                Log "[#$($recordNum.ToString().PadLeft(4))] NO MATCH"
            }
            
            # 输出每个字段的详细信息
            foreach ($c in $changes) { Log $c }
        }
        
        # 将记录写入输出流（无论是否修改）
        $outputStream.Write($recordBuffer, 0, $RecordSize)
    }
}
finally {
    # 确保文件流被正确关闭（防止资源泄露）
    $inputStream.Close()
    $outputStream.Close()
}

# ==================== 输出处理摘要 ====================

Log ""
Log ("─" * 64)
Log "处理摘要:"
Log "  修改记录数: $modifiedCount / $recordCount"
Log "  替换号码数: $replacedPhoneCount"
Log ("─" * 64)

# ==================== 保存日志文件 ====================

[System.IO.File]::WriteAllText($LogFile, $logContent.ToString())

# ==================== 显示完成信息 ====================

Write-Host ""
Write-Host "✓ 输出文件: $OutputFile" -ForegroundColor Green
Write-Host "✓ 日志文件: $LogFile" -ForegroundColor Green
