# ============================================
# DAT文件电话号码替换脚本 (中文版 - FileStream)
# 功能：根据CSV映射表替换DAT文件中的电话号码
# ============================================

param(
    [string]$FileName = "data.dat",
    [string]$MappingFile = "mapping.csv"
)

# ==================== 文件夹配置 ====================
$InFolder      = "in"
$OutFolder     = "out"
$LogFolder     = "log"
$MappingFolder = "mapping"

# ==================== 记录配置 ====================
$RecordSize   = 1300
$HeaderMarker = 0x31      # ASCII '1'
$DataMarker   = 0x32      # ASCII '2'

# ==================== 电话号码字段配置 ====================
# 定义DAT文件中电话号码的位置（可以有多个）
$PhoneFields = @(
    @{
        Name       = "Phone-1"
        StartByte  = 100          # 起始位置（1-indexed）
        Length     = 10           # 电话号码长度
    },
    @{
        Name       = "Phone-2"
        StartByte  = 200
        Length     = 10
    }
    # 添加更多字段...
)

# ==================== 脚本逻辑 ====================

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$InputFile   = Join-Path $InFolder $FileName
$OutputFile  = Join-Path $OutFolder $FileName
$MappingPath = Join-Path $MappingFolder $MappingFile
$LogFile     = Join-Path $LogFolder "$($FileName -replace '\.dat$','')_$timestamp.log"

# 创建必要的文件夹
foreach ($folder in @($OutFolder, $LogFolder)) {
    if (-not (Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null 
    }
}

# 检查文件是否存在
if (-not (Test-Path $InputFile)) {
    Write-Host "错误: DAT文件 '$InputFile' 不存在！" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $MappingPath)) {
    Write-Host "错误: 映射文件 '$MappingPath' 不存在！" -ForegroundColor Red
    exit 1
}

# ==================== 加载CSV映射表 ====================

# 读取CSV文件并构建哈希表（字典）用于快速查找
# CSV格式：OldPhone,NewPhone
$phoneMapping = @{}
$csvData = Import-Csv -Path $MappingPath -Header "OldPhone","NewPhone"

foreach ($row in $csvData) {
    if ($row.OldPhone -and $row.NewPhone) {
        $phoneMapping[$row.OldPhone.Trim()] = $row.NewPhone.Trim()
    }
}

# 日志函数
$logContent = [System.Text.StringBuilder]::new()
function Log($msg) {
    [void]$logContent.AppendLine($msg)
    Write-Host $msg
}

# 开始处理
Log "╔══════════════════════════════════════════════════════════════╗"
Log "║  DAT Phone Replacer (FileStream) - 中文版                    ║"
Log "╠══════════════════════════════════════════════════════════════╣"
Log "║  时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                               ║"
Log "║  输入:  $($InputFile.PadRight(50))║"
Log "║  输出: $($OutputFile.PadRight(50))║"
Log "║  映射: $($MappingPath.PadRight(50))║"
Log "╚══════════════════════════════════════════════════════════════╝"
Log ""
Log "已加载 $($phoneMapping.Count) 条电话号码映射规则"
Log ""

$fileInfo = Get-Item $InputFile
$fileLength = $fileInfo.Length
$recordCount = [Math]::Floor($fileLength / $RecordSize)

Log "文件大小: $fileLength 字节"
Log "记录总数: $recordCount | 字段数量: $($PhoneFields.Count)"
Log ("─" * 64)
Log ""

$modifiedCount = 0
$replacedPhoneCount = 0
$recordBuffer = New-Object byte[] $RecordSize

# 使用FileStream流式读写
$inputStream = [System.IO.File]::OpenRead($InputFile)
$outputStream = [System.IO.File]::Create($OutputFile)

try {
    for ($i = 0; $i -lt $recordCount; $i++) {
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSize)
        
        if ($bytesRead -ne $RecordSize) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] 错误 - 读取字节不足: $bytesRead / $RecordSize"
            continue
        }
        
        $recordNum = $i + 1
        $firstByte = $recordBuffer[0]
        
        if ($firstByte -eq $HeaderMarker) {
            Log "[#$($recordNum.ToString().PadLeft(4))] HEADER - 已跳过"
        }
        elseif ($firstByte -eq $DataMarker) {
            $changes = @()
            $hasChange = $false
            
            foreach ($field in $PhoneFields) {
                $fieldOffset = $field.StartByte - 1
                
                # 读取当前电话号码
                $currentPhone = [System.Text.Encoding]::ASCII.GetString($recordBuffer, $fieldOffset, $field.Length)
                
                # 检查是否在映射表中
                if ($phoneMapping.ContainsKey($currentPhone)) {
                    $newPhone = $phoneMapping[$currentPhone]
                    
                    # 验证新电话号码长度
                    if ($newPhone.Length -eq $field.Length) {
                        # 写入新电话号码
                        $newPhoneBytes = [System.Text.Encoding]::ASCII.GetBytes($newPhone)
                        [Array]::Copy($newPhoneBytes, 0, $recordBuffer, $fieldOffset, $field.Length)
                        
                        $changes += "  $($field.Name): [$currentPhone] → [$newPhone]"
                        $hasChange = $true
                        $replacedPhoneCount++
                    } else {
                        $changes += "  $($field.Name): 长度不匹配 (期望$($field.Length), 实际$($newPhone.Length))"
                    }
                } else {
                    $changes += "  $($field.Name): [$currentPhone] 无匹配"
                }
            }
            
            if ($hasChange) {
                Log "[#$($recordNum.ToString().PadLeft(4))] REPLACED"
                $modifiedCount++
            } else {
                Log "[#$($recordNum.ToString().PadLeft(4))] NO MATCH"
            }
            foreach ($c in $changes) { Log $c }
        }
        
        $outputStream.Write($recordBuffer, 0, $RecordSize)
    }
}
finally {
    $inputStream.Close()
    $outputStream.Close()
}

Log ""
Log ("─" * 64)
Log "处理摘要:"
Log "  修改记录数: $modifiedCount / $recordCount"
Log "  替换号码数: $replacedPhoneCount"
Log ("─" * 64)

[System.IO.File]::WriteAllText($LogFile, $logContent.ToString())

Write-Host ""
Write-Host "✓ 输出文件: $OutputFile" -ForegroundColor Green
Write-Host "✓ 日志文件: $LogFile" -ForegroundColor Green
