# ============================================
# DATファイル電話番号置換スクリプト (日本語版 - FileStream)
# 機能：CSVマッピングテーブルに基づいてDATファイル内の電話番号を置換
# ============================================

param(
    [string]$FileName = "data.dat",
    [string]$MappingFile = "mapping.csv"
)

# ==================== フォルダ設定 ====================
$InFolder      = "in"
$OutFolder     = "out"
$LogFolder     = "log"
$MappingFolder = "mapping"

# ==================== レコード設定 ====================
$RecordSize   = 1300
$HeaderMarker = 0x31      # ASCII '1'
$DataMarker   = 0x32      # ASCII '2'

# ==================== 電話番号フィールド設定 ====================
$PhoneFields = @(
    @{
        Name       = "Phone-1"
        StartByte  = 100
        Length     = 10
    },
    @{
        Name       = "Phone-2"
        StartByte  = 200
        Length     = 10
    }
)

# ==================== スクリプトロジック ====================

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$InputFile   = Join-Path $InFolder $FileName
$OutputFile  = Join-Path $OutFolder $FileName
$MappingPath = Join-Path $MappingFolder $MappingFile
$LogFile     = Join-Path $LogFolder "$($FileName -replace '\.dat$','')_$timestamp.log"

foreach ($folder in @($OutFolder, $LogFolder)) {
    if (-not (Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null 
    }
}

if (-not (Test-Path $InputFile)) {
    Write-Host "エラー: DATファイル '$InputFile' が存在しません！" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $MappingPath)) {
    Write-Host "エラー: マッピングファイル '$MappingPath' が存在しません！" -ForegroundColor Red
    exit 1
}

# ==================== CSVマッピングテーブルを読み込む ====================

$phoneMapping = @{}
$csvData = Import-Csv -Path $MappingPath -Header "OldPhone","NewPhone"

foreach ($row in $csvData) {
    if ($row.OldPhone -and $row.NewPhone) {
        $phoneMapping[$row.OldPhone.Trim()] = $row.NewPhone.Trim()
    }
}

$logContent = [System.Text.StringBuilder]::new()
function Log($msg) {
    [void]$logContent.AppendLine($msg)
    Write-Host $msg
}

Log "╔══════════════════════════════════════════════════════════════╗"
Log "║  DAT Phone Replacer (FileStream) - 日本語版                  ║"
Log "╠══════════════════════════════════════════════════════════════╣"
Log "║  時刻: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                               ║"
Log "║  入力:  $($InputFile.PadRight(50))║"
Log "║  出力: $($OutputFile.PadRight(50))║"
Log "║  マッピング: $($MappingPath.PadRight(44))║"
Log "╚══════════════════════════════════════════════════════════════╝"
Log ""
Log "$($phoneMapping.Count) 件の電話番号マッピングルールを読み込みました"
Log ""

$fileInfo = Get-Item $InputFile
$fileLength = $fileInfo.Length
$recordCount = [Math]::Floor($fileLength / $RecordSize)

Log "ファイルサイズ: $fileLength バイト"
Log "レコード数: $recordCount | フィールド数: $($PhoneFields.Count)"
Log ("─" * 64)
Log ""

$modifiedCount = 0
$replacedPhoneCount = 0
$recordBuffer = New-Object byte[] $RecordSize

$inputStream = [System.IO.File]::OpenRead($InputFile)
$outputStream = [System.IO.File]::Create($OutputFile)

try {
    for ($i = 0; $i -lt $recordCount; $i++) {
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSize)
        
        if ($bytesRead -ne $RecordSize) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] エラー - 読み込みバイト不足: $bytesRead / $RecordSize"
            continue
        }
        
        $recordNum = $i + 1
        $firstByte = $recordBuffer[0]
        
        if ($firstByte -eq $HeaderMarker) {
            Log "[#$($recordNum.ToString().PadLeft(4))] ヘッダー - スキップ"
        }
        elseif ($firstByte -eq $DataMarker) {
            $changes = @()
            $hasChange = $false
            
            foreach ($field in $PhoneFields) {
                $fieldOffset = $field.StartByte - 1
                $currentPhone = [System.Text.Encoding]::ASCII.GetString($recordBuffer, $fieldOffset, $field.Length)
                
                if ($phoneMapping.ContainsKey($currentPhone)) {
                    $newPhone = $phoneMapping[$currentPhone]
                    
                    if ($newPhone.Length -eq $field.Length) {
                        $newPhoneBytes = [System.Text.Encoding]::ASCII.GetBytes($newPhone)
                        [Array]::Copy($newPhoneBytes, 0, $recordBuffer, $fieldOffset, $field.Length)
                        
                        $changes += "  $($field.Name): [$currentPhone] → [$newPhone]"
                        $hasChange = $true
                        $replacedPhoneCount++
                    } else {
                        $changes += "  $($field.Name): 長さ不一致 (期待$($field.Length), 実際$($newPhone.Length))"
                    }
                } else {
                    $changes += "  $($field.Name): [$currentPhone] マッチなし"
                }
            }
            
            if ($hasChange) {
                Log "[#$($recordNum.ToString().PadLeft(4))] 置換済み"
                $modifiedCount++
            } else {
                Log "[#$($recordNum.ToString().PadLeft(4))] マッチなし"
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
Log "サマリー:"
Log "  修正レコード数: $modifiedCount / $recordCount"
Log "  置換電話番号数: $replacedPhoneCount"
Log ("─" * 64)

[System.IO.File]::WriteAllText($LogFile, $logContent.ToString())

Write-Host ""
Write-Host "✓ 出力: $OutputFile" -ForegroundColor Green
Write-Host "✓ ログ: $LogFile" -ForegroundColor Green
