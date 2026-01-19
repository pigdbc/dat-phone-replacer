# ============================================
# DATファイル電話番号置換スクリプト (日本語版 - BigEndianUnicode)
# 機能：CSVマッピングテーブルに基づいてDATファイル内の電話番号を置換
# 対応：UTF-16BE (BigEndianUnicode) エンコード
# ============================================

param(
    [string]$FileName = "data.dat"
)

# ==================== フォルダ設定 ====================
$BaseDir = $PSScriptRoot
$InFolder = Join-Path $BaseDir "in"
$OutFolder = Join-Path $BaseDir "out"
$LogFolder = Join-Path $BaseDir "log"

# ==================== 設定ファイル読込 ====================
$ConfigFile = Join-Path $BaseDir "config.ini"
if ($args.Count -gt 0) { $ConfigFile = Join-Path $BaseDir $args[0] }

if (-not (Test-Path $ConfigFile)) {
    Write-Host "エラー: 設定ファイル '$ConfigFile' が見つかりません！" -ForegroundColor Red
    exit 1
}

function Parse-IniFile {
    param([string]$FilePath)
    $ini = @{}
    $section = "Global"
    
    Get-Content $FilePath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(";") -or $line.StartsWith("#")) { return }
        
        if ($line -match "^\[(.*)\]$") {
            $section = $matches[1]
            $ini[$section] = @{}
        }
        elseif ($line -match "^(.*?)=(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if (-not $ini.ContainsKey($section)) { $ini[$section] = @{} }
            $ini[$section][$key] = $value
        }
    }
    return $ini
}

$ConfigData = Parse-IniFile -FilePath $ConfigFile

# ==================== レコード設定 (INIから読込, 文字数) ====================
if ($ConfigData.ContainsKey("Settings")) {
    $RecordSizeChars = if ($ConfigData["Settings"]["RecordSize"]) { [int]$ConfigData["Settings"]["RecordSize"] } else { 1300 }
    $HeaderMarker = if ($ConfigData["Settings"]["HeaderMarker"]) { [int]$ConfigData["Settings"]["HeaderMarker"] + 0x30 } else { 0x31 }
    $DataMarker = if ($ConfigData["Settings"]["DataMarker"]) { [int]$ConfigData["Settings"]["DataMarker"] + 0x30 } else { 0x32 }
    $MappingFolderName = if ($ConfigData["Settings"]["MappingFolder"]) { $ConfigData["Settings"]["MappingFolder"] } else { "mapping" }
    $MappingFileName = if ($ConfigData["Settings"]["MappingFile"]) { $ConfigData["Settings"]["MappingFile"] } else { "mapping.csv" }
}
else {
    $RecordSizeChars = 1300
    $HeaderMarker = 0x31
    $DataMarker = 0x32
    $MappingFolderName = "mapping"
    $MappingFileName = "mapping.csv"
}

# ==================== 電話番号フィールド設定 (INIから読込) ====================
$PhoneFields = @()
foreach ($key in $ConfigData.Keys) {
    if ($key -like "Phone-*") {
        $section = $ConfigData[$key]
        if ($section["StartByte"] -and $section["Length"]) {
            $PhoneFields += @{
                Name      = if ($section["Name"]) { $section["Name"] } else { $key }
                StartByte = [int]$section["StartByte"]
                Length    = [int]$section["Length"]
            }
        }
    }
}

if ($PhoneFields.Count -eq 0) {
    Write-Host "エラー: 設定ファイルに電話番号フィールドがありません！" -ForegroundColor Red
    exit 1
}

$PhoneFields = $PhoneFields | Sort-Object StartByte

# ==================== スクリプトロジック ====================

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$InputFile = Join-Path $InFolder $FileName
$OutputFile = Join-Path $OutFolder $FileName
$MappingFolder = if ([System.IO.Path]::IsPathRooted($MappingFolderName)) { $MappingFolderName } else { Join-Path $BaseDir $MappingFolderName }
if ([System.IO.Path]::IsPathRooted($MappingFileName)) {
    $MappingPath = $MappingFileName
}
else {
    $MappingPath = Join-Path $MappingFolder $MappingFileName
}
$LogFile = Join-Path $LogFolder "$($FileName -replace '\.dat$','')_$timestamp.log"

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
$csvData = Import-Csv -Path $MappingPath -Header "OldPhone", "NewPhone"

foreach ($row in $csvData) {
    if ($row.OldPhone -and $row.NewPhone) {
        if ($row.OldPhone.Trim() -eq "OldPhone" -and $row.NewPhone.Trim() -eq "NewPhone") { continue }
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
Log "║  設定: $($ConfigFile.PadRight(50))║"
Log "║  マッピング: $($MappingPath.PadRight(44))║"
Log "╚══════════════════════════════════════════════════════════════╝"
Log ""
Log "$($phoneMapping.Count) 件の電話番号マッピングルールを読み込みました"
Log ""

$fileInfo = Get-Item $InputFile
$fileLength = $fileInfo.Length
$recordCount = [Math]::Floor($fileLength / ($RecordSizeChars * 2))

Log "ファイルサイズ: $fileLength バイト"
Log "レコード数: $recordCount | フィールド数: $($PhoneFields.Count)"
Log ("─" * 64)
Log ""

$modifiedCount = 0
$replacedPhoneCount = 0
$RecordSizeBytes = $RecordSizeChars * 2
$recordBuffer = New-Object byte[] $RecordSizeBytes

$inputStream = [System.IO.File]::OpenRead($InputFile)
$outputStream = [System.IO.File]::Create($OutputFile)

try {
    for ($i = 0; $i -lt $recordCount; $i++) {
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSizeBytes)
        
        if ($bytesRead -ne $RecordSizeBytes) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] エラー - 読み込みバイト不足: $bytesRead / $RecordSizeBytes"
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
                $fieldOffset = ($field.StartByte - 1) * 2
                $byteLen = $field.Length * 2
                $phoneBytes = New-Object byte[] $byteLen
                [Array]::Copy($recordBuffer, $fieldOffset, $phoneBytes, 0, $byteLen)
                $currentPhoneRaw = [System.Text.Encoding]::BigEndianUnicode.GetString($phoneBytes)
                $currentPhone = $currentPhoneRaw.Trim([char]0).Trim()
                
                if ($phoneMapping.ContainsKey($currentPhone)) {
                    $newPhone = $phoneMapping[$currentPhone]
                    
                    $newPhoneBytes = [System.Text.Encoding]::BigEndianUnicode.GetBytes($newPhone)
                    if ($newPhoneBytes.Length -eq $byteLen) {
                        [Array]::Copy($newPhoneBytes, 0, $recordBuffer, $fieldOffset, $byteLen)
                        
                        $changes += "  $($field.Name): [$currentPhone] → [$newPhone]"
                        $hasChange = $true
                        $replacedPhoneCount++
                    }
                    else {
                        $changes += "  $($field.Name): 長さ不一致 (期待$($field.Length), 実際$($newPhone.Length))"
                    }
                }
                else {
                    $changes += "  $($field.Name): [$currentPhone] マッチなし"
                }
            }
            
            if ($hasChange) {
                Log "[#$($recordNum.ToString().PadLeft(4))] 置換済み"
                $modifiedCount++
            }
            else {
                Log "[#$($recordNum.ToString().PadLeft(4))] マッチなし"
            }
            foreach ($c in $changes) { Log $c }
        }
        
        $outputStream.Write($recordBuffer, 0, $RecordSizeBytes)
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
