# ==============================================================================
# VRC設定インポート＆エクスポート.ps1
# VRChat Registry Configuration Manager (Import & Export)
# ==============================================================================
# VRChatの設定レジストリ (HKCU:\Software\VRChat\vrchat) の
# エクスポート（JSONバックアップ保存）およびインポート（復元）を1ファイルで行う統合ツールです。
# ==============================================================================

[CmdletBinding(DefaultParameterSetName = "Interactive")]
param (
    [Parameter(ParameterSetName = "Export")]
    [switch]$Export,

    [Parameter(ParameterSetName = "Import")]
    [switch]$Import,

    [Parameter(ParameterSetName = "Export")]
    [Parameter(ParameterSetName = "Import")]
    [Parameter(ParameterSetName = "Interactive")]
    [string]$FilePath,

    [Parameter(ParameterSetName = "Export")]
    [Parameter(ParameterSetName = "Interactive")]
    [switch]$IncludeTimestampBackup,

    [Parameter(ParameterSetName = "Import")]
    [switch]$DryRun,

    [Parameter(ParameterSetName = "Import")]
    [switch]$NoBackup,

    [switch]$Silent
)

# 文字コード保証 (UTF-8)
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrEmpty($ScriptDir)) {
    $ScriptDir = $PSScriptRoot
}
if ([string]::IsNullOrEmpty($ScriptDir)) {
    $ScriptDir = (Get-Location).Path
}

$RegistrySubPath = "Software\VRChat\vrchat"

function Resolve-ConfigPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return (Join-Path $ScriptDir "vrc_config_personal.json")
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return (Join-Path $ScriptDir $Path)
}

# ------------------------------------------------------------------------------
# エクスポート処理
# ------------------------------------------------------------------------------
function Invoke-VRChatExport([string]$TargetFile, [switch]$MakeTimestampBackup, [switch]$IsSilent) {
    $TargetFile = Resolve-ConfigPath $TargetFile
    $RegKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($RegistrySubPath, $false)

    if ($null -eq $RegKey) {
        Write-Error "VRChat の設定レジストリ (HKCU:\$RegistrySubPath) が見つかりませんでした。"
        return $false
    }

    if (-not $IsSilent) {
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host " VRChat 設定エクスポート" -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "ターゲット: HKCU:\$RegistrySubPath" -ForegroundColor Gray
    }

    $ValueNames = $RegKey.GetValueNames()
    $SettingsMap = [ordered]@{}
    $Count = 0

    foreach ($Name in $ValueNames) {
        $Kind = $RegKey.GetValueKind($Name)
        $RawVal = $RegKey.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $KindStr = $Kind.ToString()

        # Unity PlayerPrefs の float/double 等で 64bit 値が DWord に格納されている場合の型補正
        if ($Kind -eq [Microsoft.Win32.RegistryValueKind]::DWord -and $RawVal -is [int64]) {
            if ($RawVal -gt [uint32]::MaxValue -or $RawVal -lt [int]::MinValue) {
                $KindStr = "QWord"
            }
        }

        $Entry = [ordered]@{
            "type" = $KindStr
        }

        switch ($Kind) {
            ([Microsoft.Win32.RegistryValueKind]::Binary) {
                if ($null -ne $RawVal -and $RawVal -is [byte[]]) {
                    $Entry["value"] = [Convert]::ToBase64String($RawVal)
                } else {
                    $Entry["value"] = ""
                }
            }
            ([Microsoft.Win32.RegistryValueKind]::DWord) {
                $Entry["value"] = [int64]$RawVal
            }
            ([Microsoft.Win32.RegistryValueKind]::QWord) {
                $Entry["value"] = [int64]$RawVal
            }
            ([Microsoft.Win32.RegistryValueKind]::MultiString) {
                $Entry["value"] = [string[]]$RawVal
            }
            default {
                $Entry["value"] = [string]$RawVal
            }
        }

        $SettingsMap[$Name] = $Entry
        $Count++
    }

    $RegKey.Close()

    $ExportData = [ordered]@{
        "metadata" = [ordered]@{
            "exporter"      = "VRChat Configuration Manager"
            "version"       = "2.0.0"
            "exported_at"   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
            "machine_name"  = $env:COMPUTERNAME
            "entry_count"   = $Count
            "registry_root" = "HKEY_CURRENT_USER\$RegistrySubPath"
        }
        "settings" = $SettingsMap
    }

    $JsonOutput = $ExportData | ConvertTo-Json -Depth 10

    $ParentDir = Split-Path -Parent $TargetFile
    if ($ParentDir -and -not (Test-Path $ParentDir)) {
        New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($TargetFile, $JsonOutput, [System.Text.Encoding]::UTF8)

    if (-not $IsSilent) {
        Write-Host "[OK] エクスポート完了: $TargetFile (合計 $Count 項目)" -ForegroundColor Green
    }

    if ($MakeTimestampBackup) {
        $TimeStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $BackupFile = Join-Path (Split-Path -Parent $TargetFile) "vrc_config_backup_$TimeStamp.json"
        [System.IO.File]::WriteAllText($BackupFile, $JsonOutput, [System.Text.Encoding]::UTF8)
        if (-not $IsSilent) {
            Write-Host "[OK] 日時付きバックアップ保存: $BackupFile" -ForegroundColor Cyan
        }
    }

    return $true
}

# ------------------------------------------------------------------------------
# インポート処理
# ------------------------------------------------------------------------------
function Invoke-VRChatImport([string]$SourceFile, [switch]$IsDryRun, [switch]$SkipBackup, [switch]$IsSilent) {
    $SourceFile = Resolve-ConfigPath $SourceFile

    if (-not (Test-Path $SourceFile)) {
        Write-Error "インポート元の JSON ファイルが存在しません: $SourceFile"
        return $false
    }

    if (-not $IsSilent) {
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host " VRChat 設定インポート" -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "入力ファイル: $SourceFile" -ForegroundColor Gray
        if ($IsDryRun) {
            Write-Host "[DRY-RUN] シミュレーションモード（レジストリの変更は行いません）" -ForegroundColor Yellow
        }
    }

    try {
        $RawJson = [System.IO.File]::ReadAllText($SourceFile, [System.Text.Encoding]::UTF8)
        $Data = $RawJson | ConvertFrom-Json
    } catch {
        Write-Error "JSON ファイルの読み込みに失敗しました: $_"
        return $false
    }

    if ($null -eq $Data.settings) {
        Write-Error "JSON 内に 'settings' オブジェクトが存在しません。"
        return $false
    }

    # インポート前バックアップの作成
    if (-not $SkipBackup -and -not $IsDryRun) {
        $TimeStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $PreBackupFile = Join-Path $ScriptDir "vrc_config_pre_import_backup_$TimeStamp.json"
        [void](Invoke-VRChatExport -TargetFile $PreBackupFile -IsSilent)
        if (-not $IsSilent) {
            Write-Host "[OK] インポート前自動バックアップ保存: $PreBackupFile" -ForegroundColor Cyan
        }
    }

    $RegKey = $null
    if (-not $IsDryRun) {
        $RegKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($RegistrySubPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
        if ($null -eq $RegKey) {
            Write-Error "レジストリ (HKCU:\$RegistrySubPath) への書き込みオープンに失敗しました。"
            return $false
        }
    }

    $SuccessCount = 0
    $ErrorCount = 0

    $SettingNames = $Data.settings | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

    foreach ($Name in $SettingNames) {
        $Item = $Data.settings.$Name
        $KindStr = $Item.type
        $Val = $Item.value

        try {
            $RegKind = [Microsoft.Win32.RegistryValueKind]::$KindStr
            $ConvertedValue = $null

            switch ($RegKind) {
                ([Microsoft.Win32.RegistryValueKind]::Binary) {
                    if ($Val -and $Val -ne "") {
                        $ConvertedValue = [Convert]::FromBase64String($Val)
                    } else {
                        $ConvertedValue = [byte[]]@()
                    }
                }
                ([Microsoft.Win32.RegistryValueKind]::DWord) {
                    $Int64Val = [int64]$Val
                    if ($Int64Val -gt [uint32]::MaxValue -or $Int64Val -lt [int]::MinValue) {
                        $RegKind = [Microsoft.Win32.RegistryValueKind]::QWord
                        $ConvertedValue = $Int64Val
                    } else {
                        $ConvertedValue = [int]$Int64Val
                    }
                }
                ([Microsoft.Win32.RegistryValueKind]::QWord) {
                    $ConvertedValue = [int64]$Val
                }
                ([Microsoft.Win32.RegistryValueKind]::MultiString) {
                    $ConvertedValue = [string[]]$Val
                }
                default {
                    $ConvertedValue = [string]$Val
                }
            }

            if (-not $IsDryRun) {
                $RegKey.SetValue($Name, $ConvertedValue, $RegKind)
            }
            $SuccessCount++
        } catch {
            $ErrorCount++
            if (-not $IsSilent) {
                Write-Warning "キーのインポート失敗: $Name ($_)"
            }
        }
    }

    if ($null -ne $RegKey) {
        $RegKey.Flush()
        $RegKey.Close()
    }

    if (-not $IsSilent) {
        Write-Host "-----------------------------------------------------" -ForegroundColor Gray
        if ($IsDryRun) {
            Write-Host "[DRY-RUN 完了] 適用予定項目数: $SuccessCount 項目 (エラー想定: $ErrorCount 件)" -ForegroundColor Yellow
        } else {
            Write-Host "[OK] インポート完了: 成功 $SuccessCount 項目 (エラー: $ErrorCount 件)" -ForegroundColor Green
        }
    }

    return ($ErrorCount -eq 0)
}

# ------------------------------------------------------------------------------
# メインディスパッチ
# ------------------------------------------------------------------------------
if ($Export) {
    [void](Invoke-VRChatExport -TargetFile $FilePath -MakeTimestampBackup:$IncludeTimestampBackup -IsSilent:$Silent)
    exit
}

if ($Import) {
    [void](Invoke-VRChatImport -SourceFile $FilePath -IsDryRun:$DryRun -SkipBackup:$NoBackup -IsSilent:$Silent)
    exit
}

# 対話モード (パラメータ未指定時)
Clear-Host
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "   VRChat 設定マネージャー (インポート & エクスポート)" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " [1] 設定をエクスポートする (JSONファイルにバックアップ保存)"
Write-Host " [2] 設定をインポートする (JSONファイルからレジストリへ復元)"
Write-Host " [3] インポートのテスト実行 (Dry-Run: 変更せずに検証)"
Write-Host " [0] 終了"
Write-Host ""
$Choice = Read-Host "番号を選択してください (1/2/3/0)"

switch ($Choice) {
    "1" {
        Write-Host ""
        [void](Invoke-VRChatExport -TargetFile $FilePath -MakeTimestampBackup)
    }
    "2" {
        Write-Host ""
        Write-Host "[警告] 現在の VRChat レジストリ設定が上書きされます。" -ForegroundColor Yellow
        $Confirm = Read-Host "復元を実行しますか？ (Y/N)"
        if ($Confirm -eq "Y" -or $Confirm -eq "y") {
            [void](Invoke-VRChatImport -SourceFile $FilePath)
        } else {
            Write-Host "キャンセルしました。" -ForegroundColor Gray
        }
    }
    "3" {
        Write-Host ""
        [void](Invoke-VRChatImport -SourceFile $FilePath -IsDryRun)
    }
    default {
        Write-Host "終了します。" -ForegroundColor Gray
    }
}
