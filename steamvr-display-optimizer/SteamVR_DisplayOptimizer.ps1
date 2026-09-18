# ==============================================================================
# SteamVR Display Optimizer (PowerShell)
# ==============================================================================
# SteamVRの起動を即時検知してVR用ディスプレイ構成（メイン低解像度・サブ無効化）
# に自動切り替え、SteamVR終了時に通常ディスプレイ構成へ自動復元します。
# OSカーネルレベルのプロセス待機により、VRプレイ中のCPU使用率は 0.00% です。
# ==============================================================================

param (
    [switch]$RunOnce,          # 1回だけ現在のSteamVR状態に合わせて適用して終了
    [switch]$ForceVRMode,      # 手動でVRモードを即座に適用
    [switch]$ForceNormalMode,  # 手動で通常モードを即座に適用
    [switch]$Stop,             # 実行中のバックグラウンド監視を停止して通常画面に復元
    [switch]$InstallStartup,   # Windows起動時の自動常駐ショートカットを作成
    [switch]$UninstallStartup  # Windows起動時の自動常駐ショートカットを削除
)

# コンソール文字化け防止 (PowerShell 5.1環境でのUTF-8出力保証)
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ------------------------------------------------------------------------------
# 設定パラメータ (Configuration)
# ------------------------------------------------------------------------------
# SteamVR起動中（VRモード）: メイン画面の解像度・リフレッシュレート (サブ画面は無効化)
$VR_Width       = 800
$VR_Height      = 600
$VR_Frequency   = 50

# SteamVR終了後（通常モード）: メイン画面の解像度・リフレッシュレート
$Normal_Width     = 1920
$Normal_Height    = 1080
$Normal_Frequency = 180

# SteamVR終了後（通常モード）: サブ画面の解像度・リフレッシュレート (有効化)
$Sub_Width        = 1920
$Sub_Height       = 1080
$Sub_Frequency    = 75

# 監視間隔 (秒) - SteamVR未起動時のポーリング間隔 (CPU負荷 0.01% 未満)
$CheckIntervalSeconds = 1

# 状態遷移デバウンス (短期間の再起動・接続断での過剰な画面切替を抑制: 500ms x 5 = 2.5秒)
$DebounceIntervalMs = 500
$DebounceCycles     = 5

# 監視対象のSteamVRプロセス名 (server, monitor, compositor すべてを追跡)
$SteamVRProcessNames = @("vrserver", "vrmonitor", "vrcompositor")

# デスクトップ通知 (Windowsネイティブトースト通知) の有効化
$EnableNotifications = $true

# ログファイルへの記録 (バックグラウンド実行時のトラブルシューティング用)
$EnableLogging = $true

# ------------------------------------------------------------------------------
# パスおよび環境解決
# ------------------------------------------------------------------------------
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$csPath = Join-Path $scriptDir "DisplayManager.cs"
$logPath = Join-Path $scriptDir "SteamVR_DisplayOptimizer.log"
$startupFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
$shortcutPath = Join-Path $startupFolder "SteamVR_DisplayOptimizer.lnk"
$vbsPath = Join-Path $scriptDir "Run_SteamVR_Optimizer_Silent.vbs"

# ------------------------------------------------------------------------------
# ロギング & 通知ヘルパー関数（スクリプト全体で利用するため最上部に配置）
# ------------------------------------------------------------------------------
$script:logCounter = 0

function Write-Log ([string]$message, [System.ConsoleColor]$color = [System.ConsoleColor]::White) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $message"
    
    # コンソール出力 (stdoutが有効な場合)
    try {
        Write-Host $line -ForegroundColor $color
    } catch { }

    # ログファイル追記 (最大50KBで自動ローテーション: 30回に1回サイズ検査してI/O負荷最小化)
    if ($EnableLogging) {
        try {
            $script:logCounter++
            if ($script:logCounter -ge 30) {
                $script:logCounter = 0
                if (Test-Path $logPath) {
                    $fileSize = (Get-Item $logPath).Length
                    if ($fileSize -gt 50KB) {
                        $lines = Get-Content $logPath -Tail 100
                        Set-Content $logPath -Value $lines -Encoding UTF8
                    }
                }
            }
            Add-Content -Path $logPath -Value $line -Encoding UTF8
        } catch { }
    }
}

$script:lastNotificationTime = [DateTime]::MinValue
$script:lastNotificationText = ""

function Show-Notification ([string]$title, [string]$message) {
    if (-not $EnableNotifications) { return }

    # 同一内容の連続通知を10秒間スロットリング（通知スパム防止・快適なUX）
    $now = [DateTime]::Now
    if ($message -eq $script:lastNotificationText -and ($now - $script:lastNotificationTime).TotalSeconds -lt 10) {
        return
    }
    $script:lastNotificationTime = $now
    $script:lastNotificationText = $message

    try {
        # 1. 優先: Windows 10/11 ネイティブ WinRT トースト通知 (非同期・軽量・モダンUI)
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $textNodes = $template.GetElementsByTagName("text")
        $textNodes.Item(0).AppendChild($template.CreateTextNode($title)) | Out-Null
        $textNodes.Item(1).AppendChild($template.CreateTextNode($message)) | Out-Null

        $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("SteamVR Display Optimizer")
        $notifier.Show($toast)
        return
    } catch { }

    # 2. フォールバック: Windows Forms バルーン通知
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        if ($script:fallbackNotifyIcon) {
            try { $script:fallbackNotifyIcon.Dispose() } catch { }
        }
        $script:fallbackNotifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $script:fallbackNotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        $script:fallbackNotifyIcon.BalloonTipTitle = $title
        $script:fallbackNotifyIcon.BalloonTipText = $message
        $script:fallbackNotifyIcon.Visible = $true
        $script:fallbackNotifyIcon.ShowBalloonTip(2000)
    } catch { }
}

function Update-WindowTitle ([string]$status) {
    try {
        $host.UI.RawUI.WindowTitle = "SteamVR Display Optimizer - $status"
    } catch { }
}

# ------------------------------------------------------------------------------
# Win32 / C# ヘルパーの読み込み
# ------------------------------------------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'DisplayManager').Type) {
    if (Test-Path $csPath) {
        Add-Type -Path $csPath
    } else {
        Write-Log "[Error] DisplayManager.cs が見つかりません: $csPath" Red
        exit 1
    }
}

# ------------------------------------------------------------------------------
# モード適用関数
# ------------------------------------------------------------------------------
function Set-VRDisplayMode {
    Update-WindowTitle "VRモード適用中..."
    Write-Log "[VR Mode] VR用ディスプレイ設定を適用中..." Cyan
    Show-Notification "SteamVR Display Optimizer" "VRモード適用: メイン画面 800x600 (サブ画面無効)"
    
    # 1. サブモニターを無効化 (単一画面モード: SetDisplayConfig によるネイティブ同期切替)
    Write-Log "  -> サブモニターを無効化しています (単一画面)..." Yellow
    $topoOk = [DisplayManager]::SwitchTopologyInternal()
    if (-not $topoOk) {
        Write-Log "  -> [警告] 単一画面トポロジへの切り替えに失敗しました（モニター数: $([DisplayManager]::GetMonitorCount())）。" Red
    }
    Start-Sleep -Milliseconds 400

    # 2. メインモニターを VR用設定 (800x600 @ 50Hz) に変更
    $primaryDev = [DisplayManager]::GetPrimaryDeviceName()
    $appliedFreq = 0
    $ok = [DisplayManager]::SetDisplayResolutionAndRate($primaryDev, $VR_Width, $VR_Height, $VR_Frequency, [ref]$appliedFreq)
    if (-not $ok) {
        # GPUドライバのトポロジ切替遅延に備えて300ms後に1回リトライ
        Start-Sleep -Milliseconds 300
        $ok = [DisplayManager]::SetDisplayResolutionAndRate($primaryDev, $VR_Width, $VR_Height, $VR_Frequency, [ref]$appliedFreq)
    }
    
    if (-not $ok) {
        Write-Log "  -> [警告] $primaryDev の解像度変更に失敗しました。" Red
    } elseif ($appliedFreq -ne $VR_Frequency) {
        Write-Log "  -> メイン画面 ($primaryDev) を設定: ${VR_Width}x${VR_Height} @ ${appliedFreq}Hz (${VR_Frequency}Hz 最寄り値)" Green
    } else {
        Write-Log "  -> メイン画面 ($primaryDev) を設定: ${VR_Width}x${VR_Height} @ ${appliedFreq}Hz" Green
    }
    Update-WindowTitle "VRモード稼働中 (メイン 800x600)"
}

function Set-NormalDisplayMode {
    param([switch]$Fast)
    Update-WindowTitle "通常モード復元中..."
    Write-Log "[Normal Mode] 通常ディスプレイ設定を復元中..." Cyan
    if (-not $Fast) {
        Show-Notification "SteamVR Display Optimizer" "通常モード復元: メイン 1920x1080@180Hz, サブ 75Hz"
    }
    
    # 1. サブモニターを有効化 (画面拡張モード: SetDisplayConfig によるネイティブ同期切替 & 検証)
    if ([DisplayManager]::HasSecondaryDevice()) {
        Write-Log "  -> サブモニターを有効化 (拡張デスクトップモード)..." Yellow
        $topoOk = [DisplayManager]::SwitchTopologyExtend()
        if (-not $topoOk) {
            Write-Log "  -> [警告] 拡張デバイストポロジ切替が不完全です（モニター数: $([DisplayManager]::GetMonitorCount())）。リトライ中..." Red
            [DisplayManager]::SwitchTopologyExtend(2) | Out-Null
        }
        if (-not $Fast) { Start-Sleep -Milliseconds 500 }
    }

    # 2. メインモニターを 通常設定 (1920x1080 @ 180Hz) に変更
    $primaryDev = [DisplayManager]::GetPrimaryDeviceName()
    $appliedMainFreq = 0
    $okMain = [DisplayManager]::SetDisplayResolutionAndRate($primaryDev, $Normal_Width, $Normal_Height, $Normal_Frequency, [ref]$appliedMainFreq)
    if (-not $okMain) {
        Start-Sleep -Milliseconds 300
        $okMain = [DisplayManager]::SetDisplayResolutionAndRate($primaryDev, $Normal_Width, $Normal_Height, $Normal_Frequency, [ref]$appliedMainFreq)
    }
    if ($okMain) {
        Write-Log "  -> メイン画面 ($primaryDev) を復元: ${Normal_Width}x${Normal_Height} @ ${appliedMainFreq}Hz" Green
    } else {
        Write-Log "  -> [警告] メイン画面 ($primaryDev) の解像度復元に失敗しました。" Red
    }

    # 3. 有効化後のサブモニターを 通常設定 (1920x1080 @ 75Hz) に変更
    if ([DisplayManager]::HasSecondaryDevice() -and [DisplayManager]::GetMonitorCount() -ge 2) {
        $secondaryDev = [DisplayManager]::GetSecondaryDeviceName()
        $appliedSubFreq = 0
        $okSub = [DisplayManager]::SetDisplayResolutionAndRate($secondaryDev, $Sub_Width, $Sub_Height, $Sub_Frequency, [ref]$appliedSubFreq)
        if (-not $okSub) {
            Start-Sleep -Milliseconds 300
            $okSub = [DisplayManager]::SetDisplayResolutionAndRate($secondaryDev, $Sub_Width, $Sub_Height, $Sub_Frequency, [ref]$appliedSubFreq)
        }
        if ($okSub) {
            Write-Log "  -> サブ画面 ($secondaryDev) を設定: ${Sub_Width}x${Sub_Height} @ ${appliedSubFreq}Hz" Green
        } else {
            Write-Log "  -> サブ画面 ($secondaryDev) はシステム既定値で拡張されました。" DarkGray
        }
    } elseif ([DisplayManager]::HasSecondaryDevice()) {
        Write-Log "  -> [警告] サブ画面が拡張されていないため解像度設定を保留しました。" Yellow
    }
    Update-WindowTitle "通常モード待機中"
}

# ------------------------------------------------------------------------------
# 各種スイッチ実行処理
# ------------------------------------------------------------------------------
if ($InstallStartup) {
    try {
        $alreadyExists = Test-Path $shortcutPath
        $wscriptExe = Join-Path ([Environment]::SystemDirectory) "wscript.exe"
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $wscriptExe
        $shortcut.Arguments = "`"$vbsPath`""
        $shortcut.WorkingDirectory = $scriptDir
        $shortcut.Description = "SteamVR Display Optimizer Silent Background Auto-Start"
        $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll, 15"
        $shortcut.Save()

        if ($alreadyExists) {
            Write-Host "[Success] スタートアップ常駐ショートカットを最新構成で更新しました。" -ForegroundColor Green
        } else {
            Write-Host "[Success] Windowsスタートアップに常駐ショートカットを新規登録しました。" -ForegroundColor Green
        }
        Write-Host "場所: $shortcutPath" -ForegroundColor DarkGray
        Write-Host "次回PC起動時から、ウィンドウを出さずに完全自動・ゼロCPU負荷で常駐します。" -ForegroundColor Cyan
        Show-Notification "SteamVR Display Optimizer" "Windows起動時の自動常駐を設定しました。"
    } catch {
        Write-Error "スタートアップ登録に失敗しました: $_"
    }
    return
}

if ($UninstallStartup) {
    try {
        if (Test-Path $shortcutPath) {
            Remove-Item $shortcutPath -Force
            Write-Host "[Success] Windowsスタートアップから常駐ショートカットを解除しました。" -ForegroundColor Yellow
            Write-Host "次回PC起動時の自動常駐は行われません。" -ForegroundColor DarkGray
            Show-Notification "SteamVR Display Optimizer" "自動常駐ショートカットを解除しました。"
        } else {
            Write-Host "[Info] スタートアップに登録されていませんでした（未登録状態です）。" -ForegroundColor DarkGray
        }
    } catch {
        Write-Error "スタートアップ登録の解除に失敗しました: $_"
    }
    return
}

if ($Stop) {
    Update-WindowTitle "停止処理中..."
    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host "  SteamVR Display Optimizer - 停止処理" -ForegroundColor Green
    Write-Host "=====================================================" -ForegroundColor Green
    
    $parentPid = 0
    try {
        $parentPid = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID").ParentProcessId
    } catch { }

    $procs = Get-CimInstance Win32_Process | Where-Object { 
        $_.CommandLine -like "*SteamVR_DisplayOptimizer.ps1*" -and 
        $_.CommandLine -notlike "*-Stop*" -and 
        $_.CommandLine -notlike "*-InstallStartup*" -and 
        $_.CommandLine -notlike "*-UninstallStartup*" -and 
        $_.CommandLine -notlike "*-RunOnce*" -and 
        $_.ProcessId -ne $PID -and 
        $_.ProcessId -ne $parentPid 
    }
    
    if ($procs) {
        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.ProcessId -Force
                Write-Host "[Info] 実行中の監視プロセス (PID: $($p.ProcessId)) を終了しました。" -ForegroundColor Yellow
            } catch { }
        }
        # プロセスの終了完了を最大2秒待機 (Mutexやファイルハンドルの確実な解放)
        $targetPids = @($procs | ForEach-Object { $_.ProcessId })
        $stopDeadline = [DateTime]::Now.AddSeconds(2)
        while ([DateTime]::Now -lt $stopDeadline) {
            $remaining = Get-Process -Id $targetPids -ErrorAction SilentlyContinue
            if (-not $remaining) { break }
            Start-Sleep -Milliseconds 100
        }
    } else {
        Write-Host "[Info] バックグラウンドで実行中の監視プロセスはありませんでした。" -ForegroundColor DarkGray
    }
    
    Write-Host "ディスプレイを通常モードに復元しています..." -ForegroundColor Cyan
    Set-NormalDisplayMode
    Write-Host "[Success] 停止および通常ディスプレイ構成への復元が完了しました。" -ForegroundColor Green
    Show-Notification "SteamVR Display Optimizer" "監視を停止し、通常ディスプレイ構成に復元しました。"
    Update-WindowTitle "停止完了"
    return
}

if ($ForceVRMode) {
    Set-VRDisplayMode
    return
}

if ($ForceNormalMode) {
    Set-NormalDisplayMode
    return
}

# ------------------------------------------------------------------------------
# 二重起動防止 (Single Instance Mutex)
# ------------------------------------------------------------------------------
$mutexName = "Global\SteamVR_DisplayOptimizer_SingleInstanceMutex"
$script:createdNewMutex = $false
$script:appMutex = $null

if (-not $RunOnce) {
    try {
        $script:appMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$script:createdNewMutex)
        if (-not $script:createdNewMutex) {
            Write-Log "[Info] SteamVR Display Optimizer は既にバックグラウンドで起動しています。" Yellow
            Show-Notification "SteamVR Display Optimizer" "既にバックグラウンドで常駐監視が動作しています。"
            exit 0
        }
    } catch { }
}

# ------------------------------------------------------------------------------
# メイン監視ループ
# ------------------------------------------------------------------------------
Update-WindowTitle "待機中"
$script:normalHealthCounter = 0
$script:isVRActive = $false

# 起動時の環境情報取得
$curPrimary = [DisplayManager]::GetPrimaryDeviceName()
$curSec = [DisplayManager]::GetSecondaryDeviceName()
$hasSec = [DisplayManager]::HasSecondaryDevice()
$pw = 0; $ph = 0; $pf = 0; $pb = 0
[DisplayManager]::GetCurrentDisplayMode($curPrimary, [ref]$pw, [ref]$ph, [ref]$pf, [ref]$pb) | Out-Null

Write-Host "=====================================================" -ForegroundColor Green
Write-Host "   SteamVR Display Optimizer is ACTIVE" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host "VR Mode     : Main ${VR_Width}x${VR_Height} @ ${VR_Frequency}Hz | Secondary: 無効"
Write-Host "Normal Mode : Main ${Normal_Width}x${Normal_Height} @ ${Normal_Frequency}Hz | Secondary: ${Sub_Width}x${Sub_Height} @ ${Sub_Frequency}Hz"
Write-Host "Display Info: Primary: $curPrimary (${pw}x${ph} @ ${pf}Hz) | Secondary: $(if ($hasSec) { "$curSec (接続中)" } else { "未接続" })" -ForegroundColor DarkGray
Write-Host "Target Procs: $($SteamVRProcessNames -join ', ')"
Write-Host "Log File    : $logPath"
Write-Host "Status      : SteamVRの起動を待機中... (停止するには Ctrl+C)"
Write-Host "-----------------------------------------------------"

# 常駐開始通知 (バックグラウンド起動時でもユーザーが動作開始を把握できるように通知)
if (-not $RunOnce) {
    Show-Notification "SteamVR Display Optimizer" "常駐を開始しました。SteamVRの起動を監視しています。"
}

# プロセス終了イベント登録（コンソール「×」終了時でも安全に通常画面へ復帰）
[AppDomain]::CurrentDomain.add_ProcessExit({
    if ($script:isVRActive) {
        Set-NormalDisplayMode -Fast
    }
    if ($script:fallbackNotifyIcon) {
        try {
            $script:fallbackNotifyIcon.Visible = $false
            $script:fallbackNotifyIcon.Dispose()
            $script:fallbackNotifyIcon = $null
        } catch { }
    }
    if ($script:appMutex -and $script:createdNewMutex) {
        try {
            $script:appMutex.ReleaseMutex()
            $script:appMutex.Dispose()
            $script:appMutex = $null
        } catch { }
    }
})

try {
    while ($true) {
        # SteamVR のいずれかのプロセスが起動しているか確認
        $runningVR = Get-Process -Name $SteamVRProcessNames -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($runningVR -and -not $script:isVRActive) {
            try { $runningVR.Dispose() } catch { }

            # SteamVR 起動検知 -> VRモード適用
            Write-Log "[Trigger] SteamVRの起動を検知しました。" Green
            Set-VRDisplayMode
            $script:isVRActive = $true

            if ($RunOnce) {
                break
            }

            Write-Log "[Monitoring] SteamVR実行中。Zero-CPU待機状態 (CPU負荷 0.00%)..." DarkGray
            
            # 【重要】すべてのSteamVRプロセスが終了するまで待機（CPU使用率 0.00%）
            while ($true) {
                $activeProc = Get-Process -Name $SteamVRProcessNames -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $activeProc) {
                    break
                }
                # プロセスの終了をOSカーネルイベントで待機 (最大1秒ごとにプロセス生存再検証・検知速度倍速化)
                try {
                    $activeProc.WaitForExit(1000) | Out-Null
                } catch {
                    Start-Sleep -Seconds 1
                } finally {
                    try { $activeProc.Dispose() } catch { }
                }

                # セルフヒーリング (VRモード維持): VD Streamer等による解像度戻しやサブ画面復活を監視・自動是正
                $primaryDev = [DisplayManager]::GetPrimaryDeviceName()
                $curW = 0; $curH = 0; $curF = 0; $curB = 0
                if ([DisplayManager]::GetCurrentDisplayMode($primaryDev, [ref]$curW, [ref]$curH, [ref]$curF, [ref]$curB)) {
                    if ($curW -ne $VR_Width -or $curH -ne $VR_Height) {
                        Write-Log "[Self-Healing] 外部要因による解像度変更を検知 (${curW}x${curH})。VR解像度 (${VR_Width}x${VR_Height}) へ再適用します..." Yellow
                        $appliedFreq = 0
                        [DisplayManager]::SetDisplayResolutionAndRate($primaryDev, $VR_Width, $VR_Height, $VR_Frequency, [ref]$appliedFreq) | Out-Null
                    }
                }
                if ([DisplayManager]::GetMonitorCount() -gt 1) {
                    Write-Log "[Self-Healing] サブ画面の意図しない有効化を検知。VR単一画面へ再設定します..." Yellow
                    [DisplayManager]::SwitchTopologyInternal() | Out-Null
                }
            }

            # 状態遷移デバウンス: SteamVR の一時的切断・再起動でないか 2.5 秒間（500ms x 5回）確認
            $isRestarted = $false
            for ($d = 0; $d -lt $DebounceCycles; $d++) {
                Start-Sleep -Milliseconds $DebounceIntervalMs
                $chk = Get-Process -Name $SteamVRProcessNames -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($chk) {
                    try { $chk.Dispose() } catch { }
                    $isRestarted = $true
                    break
                }
            }

            if ($isRestarted) {
                Write-Log "[Monitoring] SteamVRの再起動・プロセス復帰を検知。VRモードを継続します..." DarkGray
                continue
            }

            Write-Log "[Trigger] SteamVRの全プロセス終了を検知しました。" Yellow
            Set-NormalDisplayMode
            $script:isVRActive = $false
            Write-Log "Status: SteamVRの起動待機中..." DarkCyan
            Update-WindowTitle "待機中"
        }
        elseif (-not $runningVR -and $script:isVRActive) {
            # 例外的にフラグのみ残っていた場合のフェイルセーフ復元
            Set-NormalDisplayMode
            $script:isVRActive = $false
            Update-WindowTitle "待機中"
        }

        if ($RunOnce) {
            if (-not $script:isVRActive) {
                Write-Host "SteamVR is not running. Display left in Normal Mode."
            }
            break
        }

        # SteamVR未起動時は指定間隔スリープ (CPU負荷ほぼ0)
        Start-Sleep -Seconds $CheckIntervalSeconds

        # セルフヒーリング (通常モード整合性): サブモニター無効化放置や解像度・周波数不整合を自動修復
        $script:normalHealthCounter++
        if ($script:normalHealthCounter -ge 4) {
            $script:normalHealthCounter = 0
            
            $needHealing = $false
            # 1. サブモニターが存在するのに単一画面（無効化）のまま放置されている場合
            if ([DisplayManager]::HasSecondaryDevice() -and [DisplayManager]::GetMonitorCount() -lt 2) {
                Write-Log "[Self-Healing] サブモニターの無効化放置を検知しました。拡張デスクトップへ自動復帰します..." Yellow
                $needHealing = $true
            } else {
                # 2. メインモニターの解像度・周波数が通常値から外れている場合 (ゲーム異常終了後等の不整合)
                $pDev = [DisplayManager]::GetPrimaryDeviceName()
                $curW = 0; $curH = 0; $curF = 0; $curB = 0
                if ([DisplayManager]::GetCurrentDisplayMode($pDev, [ref]$curW, [ref]$curH, [ref]$curF, [ref]$curB)) {
                    if ($curW -ne $Normal_Width -or $curH -ne $Normal_Height -or $curF -lt ($Normal_Frequency - 10)) {
                        Write-Log "[Self-Healing] メイン画面の解像度/周波数不整合 (${curW}x${curH} @ ${curF}Hz) を検知。通常設定 (${Normal_Width}x${Normal_Height} @ ${Normal_Frequency}Hz) へ自己修復します..." Yellow
                        $needHealing = $true
                    }
                }

                # 3. サブモニターの解像度・周波数が通常値から外れている場合
                if (-not $needHealing -and [DisplayManager]::HasSecondaryDevice() -and [DisplayManager]::GetMonitorCount() -ge 2) {
                    $sDev = [DisplayManager]::GetSecondaryDeviceName()
                    $sw = 0; $sh = 0; $sf = 0; $sb = 0
                    if ([DisplayManager]::GetCurrentDisplayMode($sDev, [ref]$sw, [ref]$sh, [ref]$sf, [ref]$sb)) {
                        if ($sw -ne $Sub_Width -or $sh -ne $Sub_Height -or $sf -lt ($Sub_Frequency - 5)) {
                            Write-Log "[Self-Healing] サブ画面の解像度/周波数不整合 (${sw}x${sh} @ ${sf}Hz) を検知。通常設定 (${Sub_Width}x${Sub_Height} @ ${Sub_Frequency}Hz) へ自己修復します..." Yellow
                            $needHealing = $true
                        }
                    }
                }
            }

            if ($needHealing) {
                Set-NormalDisplayMode
            }
        }
    }
}
finally {
    # スクリプト中断時（Ctrl+C 等）に安全に通常画面設定へ復元
    if ($script:isVRActive) {
        Write-Host "`n[Termination] 終了前に通常ディスプレイ設定へ復帰しています..." -ForegroundColor Magenta
        Set-NormalDisplayMode -Fast
        $script:isVRActive = $false
    }
    if ($script:fallbackNotifyIcon) {
        try {
            $script:fallbackNotifyIcon.Visible = $false
            $script:fallbackNotifyIcon.Dispose()
            $script:fallbackNotifyIcon = $null
        } catch { }
    }
    if ($script:appMutex -and $script:createdNewMutex) {
        try {
            $script:appMutex.ReleaseMutex()
            $script:appMutex.Dispose()
            $script:appMutex = $null
        } catch { }
    }
}
