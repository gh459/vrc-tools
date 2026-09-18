#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SetWorkingDir(A_ScriptDir)

;@Ahk2Exe-SetName Window Resizer
;@Ahk2Exe-SetDescription Window Ultra-Shrink / Fullscreen / Restore Utility
;@Ahk2Exe-SetVersion 2.4.0.0
;@Ahk2Exe-SetFileVersion 2.4.0.0
;@Ahk2Exe-SetProductVersion 2.4.0.0
;@Ahk2Exe-SetCopyright Copyright (c) 2026
;@Ahk2Exe-SetOrigFilename WindowResizer.exe

OnError(GlobalErrorHandler)

GlobalErrorHandler(thrown, mode) {
    try {
        msg := "Unhandled Exception: " thrown.Message " (File: " thrown.File ", Line: " thrown.Line ")"
        WriteLog("[Fatal] " msg, "ERROR")
    }
    return true
}

; DPI仮想化によるマルチモニター・高DPI環境での座標ズレ・サイズ伸縮を完全防止 (Per-Monitor DPI Aware v2)
try {
    DllCall("SetProcessDpiAwarenessContext", "ptr", -4, "int") ; DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
} catch {
    try DllCall("SetProcessDpiAwareness", "int", 2) ; PROCESS_PER_MONITOR_DPI_AWARE
}

; ============================================================
; 管理者権限で起動（ダブルクリック時に自動でUAC昇格・フォールバック対応）
; ============================================================
full_command_line := DllCall("GetCommandLine", "str")
if !(A_IsAdmin || RegExMatch(full_command_line, " /restart(?!\S)")) {
    try {
        if A_IsCompiled
            Run '*RunAs "' A_ScriptFullPath '" /restart'
        else
            Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"'
        ExitApp
    } catch {
        ; 昇格がキャンセルまたは失敗した場合は、一般ウィンドウの操作を可能にするため通常権限でフォールバック継続
    }
}

; ============================================================
; グローバル変数 & キャッシュ
; ============================================================
global WindowStateMap        := Map()
global ModifiedHistory       := []   ; LIFO（後入れ先出し）スマート復元スタック
global LastActiveHwnd        := 0
global CachedActiveHwnd      := 0    ; ポーリング負荷ゼロ化用前フレームキャッシュ
global CachedAutoStartState  := -1   ; 自動起動判定のブロッキング解消キャッシュ (-1: 未検査, 0: 無効, 1: 有効)
global LastHotkeyTick        := 0    ; キー連打・長押し防止デバウンスタンプ
global IsHotkeysSuspended    := false
global OwnPID                := ProcessExist()

; ログ設定
global LogFilePath     := A_ScriptDir "\WindowResizer.log"
global MaxLogSizeBytes := 100 * 1024 ; 100 KB
global LogCounter      := 0

; 設定ファイル (INI) からの動的読み込み
global IniFilePath      := A_ScriptDir "\WindowResizer.ini"
global ShrinkHotkey     := "^+m"
global FullscreenHotkey := "^+f"
global RestoreHotkey    := "^+r"
global TinyWidth        := 1
global TinyHeight       := 1
global EnableSound      := 1
global EnableToolTip    := 1
global HideFromTaskbar  := 0    ; 1: 極小化時にタスクバーからも完全に消去 (ステルス), 0: 通常

global ActiveShrinkHotkey     := ""
global ActiveFullscreenHotkey := ""
global ActiveRestoreHotkey    := ""

LoadOrCreateConfig()

; 操作除外ウィンドウクラス（O(1) ハッシュ検索用 Map）
global ExcludedClassesMap := Map(
    "Progman", true,
    "WorkerW", true,
    "Shell_TrayWnd", true,
    "Shell_SecondaryTrayWnd", true,
    "NotifyIconOverflowWindow", true,
    "TaskManagerWindow", true,
    "Windows.UI.Core.CoreWindow", true,
    "Shell_LightDismissOverlay", true,
    "MultitaskingViewFrame", true,
    "XamlExplorerHostIslandWindow", true,
    "Windows.UI.Input.InputSite.WindowClass", true,
    "TopLevelWindowForOverflowXamlIsland", true,
    "XboxGameBarWindow", true
)

; ============================================================
; トレイメニュー・ツールチップ設定
; ============================================================
tray := A_TrayMenu
UpdateTrayMenuUI()

; ============================================================
; ショートカットキー設定
; ============================================================
RegisterHotkeys()

; 終了時コールバック
OnExit(AppExitHandler)

; ディスプレイ構成・解像度変更通知 (マルチモニター切断時の座標安全保護)
OnMessage(0x007E, DisplayChangeHandler) ; WM_DISPLAYCHANGE = 0x007E

; 直前アクティブウィンドウ記録用タイマー（トレイメニュー操作対策: 200ms間隔）
SetTimer(TrackActiveWindow, 200)

; 閉じたウィンドウのクリーンアップタイマー（60秒ごと）
SetTimer(CleanupClosedWindows, 60000)

; 起動ログ出力
WriteLog("Window Resizer v2.4 起動 (PID: " OwnPID ", Admin: " (A_IsAdmin ? "Yes" : "No") ", Compiled: " (A_IsCompiled ? "Yes" : "No") ")")

return

SafeIntIni(section, key, defaultVal, minVal := unset, maxVal := unset) {
    global IniFilePath
    try {
        val := IniRead(IniFilePath, section, key, String(defaultVal))
        if IsInteger(val) {
            num := Integer(val)
            if (IsSet(minVal) && num < minVal)
                return minVal
            if (IsSet(maxVal) && num > maxVal)
                return maxVal
            return num
        }
    }
    return defaultVal
}

LoadOrCreateConfig() {
    global IniFilePath, ShrinkHotkey, FullscreenHotkey, RestoreHotkey, TinyWidth, TinyHeight, EnableSound, EnableToolTip, HideFromTaskbar

    if !FileExist(IniFilePath) {
        defaultIni := "; ============================================================`r`n"
            . "; Window Resizer Configuration File`r`n"
            . "; ============================================================`r`n`r`n"
            . "[Hotkeys]`r`n"
            . "; ^ = Ctrl, ! = Alt, + = Shift, # = Win`r`n"
            . "Shrink=^+m`r`n"
            . "Fullscreen=^+f`r`n"
            . "Restore=^+r`r`n`r`n"
            . "[Settings]`r`n"
            . "; 縮小サイズ (物理ピクセル: 1以上の整数)`r`n"
            . "TinyWidth=1`r`n"
            . "TinyHeight=1`r`n`r`n"
            . "; 音響フィードバック (1: 有効, 0: 無効)`r`n"
            . "SoundFeedback=1`r`n`r`n"
            . "; ツールチップ通知表示 (1: 有効, 0: 無効)`r`n"
            . "ShowToolTips=1`r`n`r`n"
            . "; 極小化時にタスクバーからも完全に隠すステルスモード (1: 有効, 0: 通常)`r`n"
            . "HideFromTaskbar=0`r`n"
        try FileAppend(defaultIni, IniFilePath, "UTF-8")
    }

    try {
        ShrinkHotkey     := IniRead(IniFilePath, "Hotkeys", "Shrink", "^+m")
        FullscreenHotkey := IniRead(IniFilePath, "Hotkeys", "Fullscreen", "^+f")
        RestoreHotkey    := IniRead(IniFilePath, "Hotkeys", "Restore", "^+r")
        TinyWidth        := SafeIntIni("Settings", "TinyWidth", 1, 1, 500)
        TinyHeight       := SafeIntIni("Settings", "TinyHeight", 1, 1, 500)
        EnableSound      := SafeIntIni("Settings", "SoundFeedback", 1, 0, 1)
        EnableToolTip    := SafeIntIni("Settings", "ShowToolTips", 1, 0, 1)
        HideFromTaskbar  := SafeIntIni("Settings", "HideFromTaskbar", 0, 0, 1)
    }
}

RegisterHotkeys() {
    global ShrinkHotkey, FullscreenHotkey, RestoreHotkey
    global ActiveShrinkHotkey, ActiveFullscreenHotkey, ActiveRestoreHotkey

    ; 以前登録されていたホットキーを安全に解除 (動的ホットリロード対応)
    if (ActiveShrinkHotkey != "") {
        try Hotkey(ActiveShrinkHotkey, "Off")
    }
    if (ActiveFullscreenHotkey != "") {
        try Hotkey(ActiveFullscreenHotkey, "Off")
    }
    if (ActiveRestoreHotkey != "") {
        try Hotkey(ActiveRestoreHotkey, "Off")
    }

    failedKeys := ""
    try {
        Hotkey(ShrinkHotkey, ShrinkActiveWindow, "On")
        ActiveShrinkHotkey := ShrinkHotkey
    } catch {
        failedKeys .= "Shrink (" ShrinkHotkey " -> 既定 ^+m にフォールバック) "
        try {
            Hotkey("^+m", ShrinkActiveWindow, "On")
            ActiveShrinkHotkey := "^+m"
        }
    }
    try {
        Hotkey(FullscreenHotkey, ForceFullscreenWindow, "On")
        ActiveFullscreenHotkey := FullscreenHotkey
    } catch {
        failedKeys .= "Fullscreen (" FullscreenHotkey " -> 既定 ^+f にフォールバック) "
        try {
            Hotkey("^+f", ForceFullscreenWindow, "On")
            ActiveFullscreenHotkey := "^+f"
        }
    }
    try {
        Hotkey(RestoreHotkey, RestoreActiveWindow, "On")
        ActiveRestoreHotkey := RestoreHotkey
    } catch {
        failedKeys .= "Restore (" RestoreHotkey " -> 既定 ^+r にフォールバック) "
        try {
            Hotkey("^+r", RestoreActiveWindow, "On")
            ActiveRestoreHotkey := "^+r"
        }
    }
    if (failedKeys != "") {
        WriteLog("[Warning] ホットキー設定エラー: " failedKeys " (WindowResizer.ini の設定を確認してください)", "WARNING")
        ShowFeedback("⚠ ホットキー自動フォールバック:`n" failedKeys, 3000)
    }
}

ReloadConfig() {
    LoadOrCreateConfig()
    RegisterHotkeys()
    UpdateTrayMenuUI()
    ShowFeedback("⚙ 設定ファイルを再読み込みしました")
    WriteLog("[Settings] 設定ファイル (WindowResizer.ini) を再読み込み・再適用")
}

OpenConfigFile() {
    global IniFilePath
    if !FileExist(IniFilePath)
        LoadOrCreateConfig()
    try Run('notepad.exe "' IniFilePath '"')
}

; ============================================================
; 音響フィードバック (UX向上: 視線移動なしで操作成功を認知)
; ============================================================
PlayFeedbackSound(type := "info") {
    global EnableSound
    if (!EnableSound)
        return
    try {
        ; Win32 MessageBeep: 0x40 = MB_ICONASTERISK (心地よい控えめな通知音)
        DllCall("MessageBeep", "uint", 0x40)
    }
}

; ============================================================
; トレイメニュー動的更新（UI/UX向上: スマートダブルクリック & 状態表示）
; ============================================================
UpdateTrayMenuUI() {
    global WindowStateMap, IsHotkeysSuspended, HideFromTaskbar
    count := WindowStateMap.Count
    countStr := (count > 0) ? " (変更中: " count " 件)" : ""
    suspendStatus := IsHotkeysSuspended ? " [一時停止中]" : ""

    A_IconTip := "Window Resizer v2.4" countStr suspendStatus "`n極小化: " ShrinkHotkey "`n全画面: " FullscreenHotkey "`n復元: " RestoreHotkey

    tray := A_TrayMenu
    tray.Delete()
    
    titleItem := "Window Resizer v2.4" countStr suspendStatus
    tray.Add(titleItem, (*) => ShowHelpDialog())
    tray.Add()

    tray.Add("極小1x1化 (" ShrinkHotkey ")", (*) => TrayAction("shrink"))
    tray.Add("強制全画面 (" FullscreenHotkey ")", (*) => TrayAction("fullscreen"))
    
    restoreLabel := (count > 0) ? "直近のウィンドウをスマート復元 (" RestoreHotkey ")" : "元のサイズに復元 (" RestoreHotkey ")"
    tray.Add(restoreLabel, (*) => RestoreActiveWindow())

    allRestoreLabel := (count > 0) ? "すべての変更ウィンドウを一括復元 (" count " 件)" : "すべての変更ウィンドウを一括復元"
    tray.Add(allRestoreLabel, (*) => RestoreAllWindows())
    
    ; 変更中ウィンドウの有無に応じた動的グレーアウト（無駄クリックの撲滅）
    if (count > 0) {
        tray.Enable(restoreLabel)
        tray.Enable(allRestoreLabel)
        tray.Default := restoreLabel
    } else {
        tray.Disable(restoreLabel)
        tray.Disable(allRestoreLabel)
        tray.Default := titleItem
    }

    tray.Add()
    ; ステルスモード（タスクバー非表示）トグル (UI/UX向上)
    stealthLabel := (HideFromTaskbar ? "✔ 極小化時にタスクバーからも隠す (ステルス)" : "☐ 極小化時にタスクバーからも隠す (ステルス)")
    tray.Add(stealthLabel, (*) => ToggleHideFromTaskbar())

    ; Windows 起動時自動常駐トグル (非ブロッキング高速判定)
    isAuto := IsAutoStartConfigured()
    autoStartLabel := (isAuto ? "✔ Windows 起動時に自動常駐 (有効)" : "☐ Windows 起動時に自動常駐 (無効)")
    tray.Add(autoStartLabel, (*) => ToggleAutoStartSetting())

    suspendLabel := IsHotkeysSuspended ? "▶ ホットキーを再開する (Resume)" : "⏸ ホットキーを一時停止 (Suspend)"
    tray.Add(suspendLabel, (*) => ToggleSuspendHotkeys())
    tray.Add("設定ファイルを開く (Config.ini)", (*) => OpenConfigFile())
    tray.Add("設定を再読み込み (Reload Config)", (*) => ReloadConfig())
    tray.Add("ログファイルを開く (Open Log)", (*) => OpenLogFile())
    tray.Add("ヘルプ / 使い方", (*) => ShowHelpDialog())
    tray.Add("プロセス再起動 (Restart App)", (*) => Reload())
    tray.Add("終了 (Exit)", (*) => ExitApp())
}

; ============================================================
; ステルスモード（タスクバー非表示）トグル切り替え (UI/UX向上: 即時反映)
; ============================================================
ToggleHideFromTaskbar() {
    global HideFromTaskbar, IniFilePath, WindowStateMap
    HideFromTaskbar := !HideFromTaskbar
    try IniWrite(String(HideFromTaskbar), IniFilePath, "Settings", "HideFromTaskbar")

    ; 現在縮小中のウィンドウに対しても即座にステルス状態を反映
    for key, saved in WindowStateMap {
        h := Integer(key)
        if (saved["mode"] == "shrink" && WinExist("ahk_id " h)) {
            if (HideFromTaskbar) {
                WinSetExStyle("+0x80", "ahk_id " h)      ; WS_EX_TOOLWINDOW
                WinSetExStyle("-0x40000", "ahk_id " h)   ; WS_EX_APPWINDOW 除去
            } else {
                if saved.Has("exStyle")
                    WinSetExStyle(saved["exStyle"], "ahk_id " h)
            }
        }
    }

    statusText := HideFromTaskbar ? "ステルスモードを有効にしました（タスクバーからも非表示）" : "通常モードに切り替えました（タスクバーには表示）"
    ShowFeedback(statusText)
    WriteLog("[Settings] " statusText)
    UpdateTrayMenuUI()
}

; ============================================================
; 自動起動設定の検査とトグル切り替え (非ブロッキングキャッシュ化)
; ============================================================
IsAutoStartConfigured(forceCheck := false) {
    global CachedAutoStartState
    if (!forceCheck && CachedAutoStartState != -1)
        return CachedAutoStartState

    startupLnk := A_Startup "\WindowResizer.lnk"
    if FileExist(startupLnk) {
        CachedAutoStartState := 1
        return 1
    }
    try {
        exitCode := RunWait('schtasks /Query /TN "WindowResizer"', , "Hide")
        CachedAutoStartState := (exitCode == 0) ? 1 : 0
        return CachedAutoStartState
    }
    CachedAutoStartState := 0
    return 0
}

ToggleAutoStartSetting() {
    global CachedAutoStartState
    exePath := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\WindowResizer.exe"
    isAuto := IsAutoStartConfigured(true)
    if (isAuto) {
        if A_IsAdmin {
            RunWait('schtasks /Delete /TN "WindowResizer" /F', , "Hide")
            startupLnk := A_Startup "\WindowResizer.lnk"
            if FileExist(startupLnk)
                try FileDelete(startupLnk)
        } else {
            batPath := A_ScriptDir "\Uninstall_AutoStart.bat"
            if FileExist(batPath)
                Run('*RunAs "' batPath '"')
        }
        CachedAutoStartState := 0
        ShowFeedback("自動起動を解除しました")
        WriteLog("[AutoStart] 自動起動を解除")
    } else {
        if A_IsAdmin {
            RunWait('schtasks /Create /TN "WindowResizer" /TR "\"' exePath '\"" /SC ONLOGON /RL HIGHEST /F', , "Hide")
            psCmd := "$ts = Get-ScheduledTask -TaskName 'WindowResizer' -ErrorAction SilentlyContinue; if ($ts) { $ts.Settings.DisallowStartIfOnBatteries = $false; $ts.Settings.StopIfGoingOnBatteries = $false; $ts.Settings.ExecutionTimeLimit = 'PT0S'; Set-ScheduledTask -TaskName 'WindowResizer' -Settings $ts.Settings >$null 2>&1 }"
            RunWait('powershell -NoProfile -ExecutionPolicy Bypass -Command "' psCmd '"', , "Hide")
            startupLnk := A_Startup "\WindowResizer.lnk"
            if FileExist(startupLnk)
                try FileDelete(startupLnk)
        } else {
            batPath := A_ScriptDir "\Install_AutoStart.bat"
            if FileExist(batPath)
                Run('*RunAs "' batPath '"')
        }
        CachedAutoStartState := 1
        ShowFeedback("Windows 起動時の自動常駐を登録しました")
        WriteLog("[AutoStart] 自動起動を登録")
    }
    Sleep 200
    UpdateTrayMenuUI()
}

; ============================================================
; ディスプレイ構成・解像度変更ハンドラ（WM_DISPLAYCHANGE: 画面外飛び出し防止）
; ============================================================
DisplayChangeHandler(wParam, lParam, msg, hwnd) {
    global WindowStateMap, TinyWidth, TinyHeight
    WriteLog("[System] ディスプレイ構成または解像度の変更を検知 (WM_DISPLAYCHANGE)")
    for key, saved in WindowStateMap {
        h := Integer(key)
        if WinExist("ahk_id " h) {
            GetWindowWorkArea(h, &mLeft, &mTop, &mRight, &mBottom)
            if (saved["mode"] == "shrink") {
                ; 縮小中のウィンドウは現在の最寄りモニター作業領域左上へ再スナップ
                WinMove(mLeft, mTop, TinyWidth, TinyHeight, "ahk_id " h)
            } else if (saved["mode"] == "fullscreen") {
                ; 全画面ウィンドウは新しい解像度・作業領域へアトミック再適応 (画面はみ出し・隙間完全防止)
                w := mRight - mLeft
                h_size := mBottom - mTop
                DllCall("SetWindowPos", "ptr", h, "ptr", 0, "int", mLeft, "int", mTop, "int", w, "int", h_size, "uint", 0x0024)
            }
        }
    }
}

; ============================================================
; 復元先座標のマルチモニター作業領域クランプ（画面外虚空への消失防止）
; ============================================================
EnsureWindowInScreenArea(&x, &y, &w, &h) {
    monCount := MonitorGetCount()
    found := false
    targetL := 0, targetT := 0, targetR := A_ScreenWidth, targetB := A_ScreenHeight

    cx := x + (w // 2)
    cy := y + (h // 2)

    loop monCount {
        MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
        if (cx >= ml && cx <= mr && cy >= mt && cy <= mb) {
            found := true
            targetL := ml, targetT := mt, targetR := mr, targetB := mb
            break
        }
    }

    ; どのモニターにも中心点が含まれていない場合（サブ画面抜去時等）はプライマリ画面へ
    if !found {
        MonitorGetWorkArea(MonitorGetPrimary(), &targetL, &targetT, &targetR, &targetB)
        if (w > (targetR - targetL))
            w := targetR - targetL
        if (h > (targetB - targetT))
            h := targetB - targetT
        x := targetL + ((targetR - targetL - w) // 2)
        y := targetT + ((targetB - targetT - h) // 2)
    } else {
        ; 中心点が含まれるモニターが見つかった場合でも、タイトルバー（上端）が画面外に飛び出してドラッグ不能になるのを防止
        if (y < targetT)
            y := targetT
        if (x + w < targetL + 60)
            x := targetL
        if (x > targetR - 60)
            x := targetR - w
    }
}

; ============================================================
; ヘルプダイアログ表示 (UI/UX向上)
; ============================================================
ShowHelpDialog() {
    global WindowStateMap, ShrinkHotkey, FullscreenHotkey, RestoreHotkey
    count := WindowStateMap.Count
    helpText := "【Window Resizer v2.4 - 操作ガイド】`n`n"
             . "■ ショートカットキー一覧 (WindowResizer.ini で変更可能)`n"
             . "  • " ShrinkHotkey " : 極小1x1化 (トグル復元対応)`n"
             . "    → 枠線を解除し、OS描画領域を 1x1 ピクセルにクリッピング`n`n"
             . "  • " FullscreenHotkey " : 強制全画面 (トグル復元対応)`n"
             . "    → 枠なしで現在のモニター作業領域いっぱいに全画面表示`n`n"
             . "  • " RestoreHotkey " : スマート復元 (LIFO スタック)`n"
             . "    → 複数ウィンドウを極小化した後でも、直近のものから順次完全復元！`n`n"
             . "■ 主な機能・信頼性仕様 (v2.4)`n"
             . "  • ステルスモード（極小化時にタスクバーからも完全に隠す機能をトレイから切替可能）`n"
             . "  • タイトルバー飛び出し保護（復元時に画面外へはみ出さず必ず掴める位置へクランプ）`n"
             . "  • ディスプレイ構成変更耐性（WM_DISPLAYCHANGE 検知で縮小中ウィンドウを安全再スナップ）`n"
             . "  • 最前面表示 (WS_EX_TOPMOST) の正式な Z オーダー完全復元`n"
             . "  • 動的ホットリロード対応（トレイからアプリ再起動なしで設定を即時反映）`n"
             . "  • スマート・キーデバウンス（同一窓 200ms ガード / 別窓 60ms 高速連続操作）`n"
             . "  • アトミック描画復元（SetWindowPos 0x0024 によるサイズ・位置・フレーム一括適用でちらつき撲滅）`n"
             . "  • 外部設定ファイル (WindowResizer.ini) による自由なキーバインド・設定変更`n"
             . "  • Per-Monitor DPI Awareness v2 対応（混在マルチモニターで座標ズレなし）`n"
             . "  • Windows 11 角丸・ドロップシャドウのアーティファクト完全排除`n"
             . "  • 多段スマートフォーカス委譲（60階層走査＋トップレベルフォールバック）`n"
             . "  • 非ブロッキング高速トレイUI（schtasksプロセス生成ゼロ化で超高速応答）`n"
             . "  • トレイメニューからワンクリックで Windows 起動時自動常駐を切り替え`n"
             . "  • 音響フィードバック機能（視線移動なしで操作成功を認知）`n"
             . "  • LIFOスマート復元スタック（隠したウィンドウを新しい順に1つずつ復元）`n"
             . "  • トレイアイコンのダブルクリックで直近ウィンドウを即時復元`n"
             . "  • アプリ終了時の未復元ウィンドウ消失防止（安全復元ダイアログ）`n"
             . "  • ホットキー一時停止 (Suspend) 機能搭載`n"
             . "  • 動作ログ自動出力＆自動ローテーション (WindowResizer.log)`n"
             . "  • 現在変更中のウィンドウ数: " count " 件`n`n"
             . "※ タスクトレイ右クリックメニューから設定ファイルの編集や各種操作が可能です。"
    MsgBox(helpText, "Window Resizer v2.4 - ヘルプ", "64")
}

; ============================================================
; ホットキー一時停止/再開 (UI/UX向上: 他アプリ衝突回避)
; ============================================================
ToggleSuspendHotkeys() {
    global IsHotkeysSuspended
    IsHotkeysSuspended := !IsHotkeysSuspended
    Suspend(IsHotkeysSuspended ? 1 : 0)
    statusText := IsHotkeysSuspended ? "⏸ ホットキーを一時停止しました" : "▶ ホットキーを再開しました"
    ShowFeedback(statusText)
    WriteLog("[Suspend] " statusText)
    UpdateTrayMenuUI()
}

; ============================================================
; キー入力デバウンス（同一窓連打ガード 200ms / 別窓高速連続操作 60ms）
; ============================================================
global LastHotkeyHwnd := 0

CheckDebounce(hwnd := 0, sameWindowDelayMs := 200, differentWindowDelayMs := 60) {
    global LastHotkeyTick, LastHotkeyHwnd
    current := A_TickCount
    if (hwnd != 0 && hwnd == LastHotkeyHwnd && (current - LastHotkeyTick < sameWindowDelayMs))
        return false
    if (current - LastHotkeyTick < differentWindowDelayMs)
        return false
    LastHotkeyTick := current
    LastHotkeyHwnd := hwnd
    return true
}

; ============================================================
; 安全かつ確実なウィンドウ前面化 (Win32 フォアグラウンドロック解除)
; ============================================================
ActivateWindowSafely(hwnd) {
    if !hwnd || !WinExist("ahk_id " hwnd)
        return
    try {
        DllCall("SetForegroundWindow", "ptr", hwnd)
        DllCall("BringWindowToTop", "ptr", hwnd)
        WinActivate("ahk_id " hwnd)
    }
}

; ============================================================
; ロギングシステム & ファイル出力（自動ローテーション・オフバイワン対策済）
; ============================================================
WriteLog(message, level := "INFO") {
    global LogFilePath, MaxLogSizeBytes, LogCounter
    try {
        ts := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        line := "[" ts "] [" level "] " message "`n"
        
        ; 30回に1回サイズ検査してログ肥大化を防止 (I/O負荷最小化: 最大100KB)
        LogCounter++
        if (LogCounter >= 30) {
            LogCounter := 0
            if FileExist(LogFilePath) {
                if (FileGetSize(LogFilePath) > MaxLogSizeBytes) {
                    try {
                        content := FileRead(LogFilePath, "UTF-8")
                        lines := StrSplit(content, "`n", "`r")
                        ; 最新100行を正確に保持 (1-based offset: lines.Length - 100 + 1)
                        if (lines.Length > 100) {
                            newContent := ""
                            startIndex := lines.Length - 100 + 1
                            loop 100 {
                                idx := startIndex + A_Index - 1
                                if (idx <= lines.Length && lines[idx] != "")
                                    newContent .= lines[idx] "`n"
                            }
                            try FileDelete(LogFilePath)
                            FileAppend(newContent, LogFilePath, "UTF-8")
                        }
                    }
                }
            }
        }
        FileAppend(line, LogFilePath, "UTF-8")
    }
}

OpenLogFile() {
    global LogFilePath
    if FileExist(LogFilePath)
        Run('notepad.exe "' LogFilePath '"')
    else
        ShowFeedback("ログファイルはまだ作成されていません")
}

; ============================================================
; アプリ終了時ハンドラ（未復元ウィンドウの消失防止・安全弁）
; ============================================================
AppExitHandler(exitReason, exitCode) {
    global WindowStateMap
    if (WindowStateMap.Count > 0) {
        ; ユーザーの明示的終了操作時
        if (exitReason == "Menu" || exitReason == "Exit") {
            res := MsgBox("極小化または全画面化されたウィンドウが " WindowStateMap.Count " 件残っています。`n`nすべてのウィンドウを元のサイズに復元してから終了しますか？`n`n【はい】すべて復元して終了（推奨）`n【いいえ】復元せずに終了`n【キャンセル】終了を取り消す", "Window Resizer - 終了確認", "35") ; 35 = Yes/No/Cancel + Question Icon
            if (res == "Cancel")
                return 1 ; 終了を中断
            if (res == "Yes")
                RestoreAllWindows(false)
        } else {
            ; ログオフ・シャットダウン・再起動時は自動で安全復元
            RestoreAllWindows(false)
        }
    }
    WriteLog("Window Resizer 終了 (Reason: " exitReason ", ExitCode: " exitCode ")")
}

; ============================================================
; 対象ウィンドウ表示名取得ヘルパー
; ============================================================
GetDisplayTitle(hwnd) {
    try {
        title := WinGetTitle("ahk_id " hwnd)
        if (title == "") {
            processName := WinGetProcessName("ahk_id " hwnd)
            title := (processName != "") ? processName : "Window (" String(hwnd) ")"
        }
        if (StrLen(title) > 28)
            title := SubStr(title, 1, 25) "..."
        return title
    }
    return "Window"
}

; ============================================================
; 直前アクティブウィンドウの記録（トレイメニュー対策）
; ============================================================
TrackActiveWindow() {
    global LastActiveHwnd, CachedActiveHwnd, WindowStateMap
    try {
        hwnd := WinExist("A")
        if (hwnd == CachedActiveHwnd)
            return
        CachedActiveHwnd := hwnd

        if hwnd && !IsExcludedWindow(hwnd) {
            LastActiveHwnd := hwnd
        }

        ; フォーカス遷移時に変更中ウィンドウがあれば終了済みウィンドウを即座に整理 (UX向上: トレイ件数即時反映)
        if (WindowStateMap.Count > 0)
            CleanupClosedWindows()
    }
}

; ============================================================
; トレイメニュー操作のハンドラ（記録済みの直前ウィンドウを使用）
; ============================================================
TrayAction(action) {
    global LastActiveHwnd
    hwnd := LastActiveHwnd
    if !hwnd || !WinExist("ahk_id " hwnd) {
        ShowFeedback("操作対象のウィンドウがありません")
        return
    }
    switch action {
        case "shrink":
            ShrinkWindow(hwnd)
        case "fullscreen":
            FullscreenWindow(hwnd)
        case "restore":
            RestoreWindow(hwnd)
    }
}

; ============================================================
; 操作除外判定（O(1) 高速 Map 判定 + 不可視ウィンドウ検査）
; ============================================================
IsExcludedWindow(hwnd) {
    global ExcludedClassesMap, OwnPID
    if !hwnd || !WinExist("ahk_id " hwnd)
        return true

    try {
        ; スクリプト自身のウィンドウを除外
        pid := WinGetPID("ahk_id " hwnd)
        if (pid == OwnPID)
            return true

        ; クラス名除外
        cls := WinGetClass("ahk_id " hwnd)
        if ExcludedClassesMap.Has(cls)
            return true

        ; サイズが 0 以下の不可視・破棄途中ウィンドウを除外
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        if (ww <= 0 || wh <= 0)
            return true
    } catch {
        return true ; ウィンドウ消失等のレースコンディション時は安全のため除外扱い
    }
    return false
}

; ============================================================
; ToolTip フィードバック表示（自動消去）
; ============================================================
HideFeedbackToolTip() {
    ToolTip()
}

ShowFeedback(text, duration := 1800) {
    global EnableToolTip
    if (!EnableToolTip)
        return
    ToolTip(text)
    SetTimer(HideFeedbackToolTip, -duration)
}

; ============================================================
; WinRestore の完了を待機（最大500ms）
; ============================================================
WaitForRestore(hwnd, timeout := 500) {
    WinRestore("ahk_id " hwnd)
    startTime := A_TickCount
    loop {
        Sleep 30
        try {
            state := WinGetMinMax("ahk_id " hwnd)
            if (state == 0)
                return true
        }
        if (A_TickCount - startTime >= timeout)
            return false
    }
}

; ============================================================
; モニター作業領域の安全な取得 (Win32 MonitorFromWindow + GetMonitorInfo)
; ============================================================
GetWindowWorkArea(hwnd, &left, &top, &right, &bottom) {
    try {
        hMon := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr") ; MONITOR_DEFAULTTONEAREST = 2
        if (hMon != 0) {
            mi := Buffer(40, 0)
            NumPut("uint", 40, mi, 0)
            if DllCall("GetMonitorInfo", "ptr", hMon, "ptr", mi, "int") {
                left   := NumGet(mi, 20, "int")
                top    := NumGet(mi, 24, "int")
                right  := NumGet(mi, 28, "int")
                bottom := NumGet(mi, 32, "int")
                return true
            }
        }
    }
    ; フォールバック: Primary Monitor
    try {
        MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
        return true
    }
    left := 0, top := 0, right := A_ScreenWidth, bottom := A_ScreenHeight
    return false
}

; ============================================================
; 変更履歴スタック管理 (LIFOスマート復元用)
; ============================================================
RemoveFromHistory(hwnd) {
    global ModifiedHistory
    newHist := []
    for h in ModifiedHistory {
        if (h != hwnd)
            newHist.Push(h)
    }
    ModifiedHistory := newHist
}

PushToHistory(hwnd) {
    global ModifiedHistory
    RemoveFromHistory(hwnd) ; 重複を排除して末尾に追加（LIFO順を最新化）
    ModifiedHistory.Push(hwnd)
}

; ============================================================
; 限界極小化処理 (1x1ピクセル・リージョンクリップ・トグル対応)
; ============================================================
ShrinkActiveWindow(*) {
    hwnd := WinExist("A")
    if !hwnd || !CheckDebounce(hwnd)
        return

    if IsExcludedWindow(hwnd) {
        ShowFeedback("システム保護ウィンドウのため操作対象外です")
        return
    }

    ShrinkWindow(hwnd)
}

; ============================================================
; Windows 11 DWM 角丸・シャドウ制御ヘルパー
; ============================================================
SetWindowCornerPreference(hwnd, preference := 1) {
    ; DWMWA_WINDOW_CORNER_PREFERENCE = 33
    ; 1 = DWMWCP_DONOTROUND (角丸なし・残差ゼロ), 0 = DWMWCP_DEFAULT (通常角丸)
    try {
        pv := Buffer(4, 0)
        NumPut("uint", preference, pv, 0)
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", 33, "ptr", pv, "uint", 4)
    }
}

; ============================================================
; ウィンドウが真に可視かつ入力可能か検査（Windows 10/11 Cloaked/仮想デスクトップ/ToolWindow除外）
; ============================================================
IsWindowVisibleAndUsable(hwnd) {
    if !hwnd || !WinExist("ahk_id " hwnd) || IsExcludedWindow(hwnd)
        return false

    try {
        style := WinGetStyle("ahk_id " hwnd)
        exStyle := WinGetExStyle("ahk_id " hwnd)

        ; 不可視、最小化、ツールウィンドウ、アクティブ化禁止ウィンドウを除外
        if !(style & 0x10000000) || (style & 0x20000000) ; !WS_VISIBLE || WS_MINIMIZE
            return false
        if (exStyle & 0x80) || (exStyle & 0x08000000)   ; WS_EX_TOOLWINDOW || WS_EX_NOACTIVATE
            return false

        ; Windows 10/11 DWM Cloaked (不可視・別仮想デスクトップ等) の検査
        cloaked := Buffer(4, 0)
        if (DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "ptr", cloaked, "uint", 4) == 0) {
            if (NumGet(cloaked, 0, "uint") != 0)
                return false
        }

        ; サイズが極小（10px以下）のウィンドウを除外
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        if (w <= 10 || h <= 10)
            return false

        return true
    } catch {
        return false
    }
}

; ============================================================
; 極小化後のスマートフォーカス委譲（背面のウィンドウへ自然にフォーカスを譲渡し作業を継続可能にする）
; ============================================================
PassFocusToNextWindow(shrunkHwnd) {
    try {
        ; 1. Zオーダー直下のウィンドウを走査（最大60階層探索）
        nextHwnd := DllCall("GetWindow", "ptr", shrunkHwnd, "uint", 2, "ptr") ; GW_HWNDNEXT = 2
        loop 60 {
            if (!nextHwnd)
                break
            if (nextHwnd != shrunkHwnd && IsWindowVisibleAndUsable(nextHwnd)) {
                ActivateWindowSafely(nextHwnd)
                return
            }
            nextHwnd := DllCall("GetWindow", "ptr", nextHwnd, "uint", 2, "ptr")
        }

        ; 2. フォールバック: 有効な最前面トップレベルウィンドウを探索してアクティブ化
        for h in WinGetList() {
            if (h != shrunkHwnd && IsWindowVisibleAndUsable(h)) {
                ActivateWindowSafely(h)
                return
            }
        }
    }
}

ShrinkWindow(hwnd) {
    global TinyWidth, TinyHeight, WindowStateMap, HideFromTaskbar, RestoreHotkey

    key := String(hwnd)
    title := GetDisplayTitle(hwnd)

    ; すでに縮小済みの場合はトグルで元の状態に復元
    if (WindowStateMap.Has(key) && WindowStateMap[key]["mode"] == "shrink") {
        WriteLog("[Shrink] トグル復元実行: " title " (HWND: " hwnd ")")
        RestoreWindowState(hwnd)
        return
    }

    ; モード変更時（fullscreen → shrink）は元の保存状態を保持したまま mode を更新
    if (WindowStateMap.Has(key)) {
        WindowStateMap[key]["mode"] := "shrink"
    } else {
        SaveWindowState(hwnd, "shrink")
    }

    try {
        state := WinGetMinMax("ahk_id " hwnd)
        if (state != 0) {
            WaitForRestore(hwnd)
        }

        ; 1. ウィンドウ枠・タイトルバーの制限を外す
        WinSetStyle("-0xC00000", "ahk_id " hwnd) ; WS_CAPTION
        WinSetStyle("-0x40000",  "ahk_id " hwnd) ; WS_SIZEBOX

        ; 2. Windows 11 の角丸描画残差を排除
        SetWindowCornerPreference(hwnd, 1)

        ; 3. 現在のモニターの左上に移動
        GetWindowWorkArea(hwnd, &mLeft, &mTop, &mRight, &mBottom)
        WinMove(mLeft, mTop, TinyWidth, TinyHeight, "ahk_id " hwnd)

        ; 4. アプリ固有の最小サイズ制限（WM_GETMINMAXINFO）を突破するため、
        ;    OSの描画領域（Window Region）を物理的に 1x1 ピクセルにクリッピング
        hRgn := DllCall("CreateRectRgn", "int", 0, "int", 0, "int", TinyWidth, "int", TinyHeight, "ptr")
        if (hRgn != 0) {
            if !DllCall("SetWindowRgn", "ptr", hwnd, "ptr", hRgn, "int", 1) {
                DllCall("DeleteObject", "ptr", hRgn) ; 失敗時は自前で破棄
            }
        }

        ; 5. ステルスモード（タスクバー非表示）の適用
        if (HideFromTaskbar) {
            WinSetExStyle("+0x80", "ahk_id " hwnd)      ; WS_EX_TOOLWINDOW (タスクバー非表示化)
            WinSetExStyle("-0x40000", "ahk_id " hwnd)   ; WS_EX_APPWINDOW 除去
        }

        ; 6. フレーム変更通知 (SWP_FRAMECHANGED | SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0037)
        try WinRedraw("ahk_id " hwnd)

        PushToHistory(hwnd)
        UpdateTrayMenuUI()

        ; 7. 極小化後、背面のウィンドウへ自然にフォーカスを委譲（UX最適化: 作業が中断されない）
        PassFocusToNextWindow(hwnd)

        PlayFeedbackSound("shrink")
        ShowFeedback("🔻 1x1 に縮小: " title "`n(" RestoreHotkey " またはトグルで復元)")
        WriteLog("[Shrink] 極小1x1化完了: " title " (HWND: " hwnd ")")
    } catch as err {
        WriteLog("[Error] 極小化処理中にエラー: " err.Message " (HWND: " hwnd ")", "ERROR")
    }
}

; ============================================================
; 強制フルスクリーン化 (トグル対応・マルチモニター対応)
; ============================================================
ForceFullscreenWindow(*) {
    hwnd := WinExist("A")
    if !hwnd || !CheckDebounce(hwnd)
        return

    if IsExcludedWindow(hwnd) {
        ShowFeedback("システム保護ウィンドウのため操作対象外です")
        return
    }

    FullscreenWindow(hwnd)
}

FullscreenWindow(hwnd) {
    global WindowStateMap, RestoreHotkey

    key := String(hwnd)
    title := GetDisplayTitle(hwnd)

    ; すでに全画面化済みの場合はトグルで元の状態に復元
    if (WindowStateMap.Has(key) && WindowStateMap[key]["mode"] == "fullscreen") {
        WriteLog("[Fullscreen] トグル復元実行: " title " (HWND: " hwnd ")")
        RestoreWindowState(hwnd)
        return
    }

    ; モード変更時（shrink → fullscreen）は元の保存状態を保持したまま mode を更新
    if (WindowStateMap.Has(key)) {
        WindowStateMap[key]["mode"] := "fullscreen"
    } else {
        SaveWindowState(hwnd, "fullscreen")
    }

    try {
        state := WinGetMinMax("ahk_id " hwnd)
        if (state != 0) {
            WaitForRestore(hwnd)
        }

        ; 縮小リージョンが残っている場合は解除
        DllCall("SetWindowRgn", "ptr", hwnd, "ptr", 0, "int", 1)

        ; ウィンドウスタイルからキャプションとサイズ変更枠を削除
        WinSetStyle("-0xC00000", "ahk_id " hwnd) ; WS_CAPTION
        WinSetStyle("-0x40000",  "ahk_id " hwnd) ; WS_SIZEBOX

        ; Windows 11 角丸を無効化（画面四隅の隙間防止）
        SetWindowCornerPreference(hwnd, 1)

        ; ウィンドウが存在するモニターの作業領域を取得
        GetWindowWorkArea(hwnd, &left, &top, &right, &bottom)
        width  := right - left
        height := bottom - top

        ; アトミックに位置・サイズ・フレーム変更を同時適用（チラつき撲滅: SWP_FRAMECHANGED | SWP_NOZORDER = 0x0024）
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", left, "int", top, "int", width, "int", height, "uint", 0x0024)
        ActivateWindowSafely(hwnd)
        try WinRedraw("ahk_id " hwnd)

        PushToHistory(hwnd)
        UpdateTrayMenuUI()

        PlayFeedbackSound("fullscreen")
        ShowFeedback("🔲 全画面化: " title "`n(" width "x" height ")")
        WriteLog("[Fullscreen] 強制全画面化完了: " title " (HWND: " hwnd ", Size: " width "x" height ")")
    } catch as err {
        WriteLog("[Error] 全画面化処理中にエラー: " err.Message " (HWND: " hwnd ")", "ERROR")
    }
}

; ============================================================
; 復元処理（LIFO スマート復元スタック & フォールバックUX最適化）
; ============================================================
RestoreActiveWindow(*) {
    global WindowStateMap, ModifiedHistory
    hwnd := WinExist("A")
    if !CheckDebounce(hwnd)
        return
    key := String(hwnd)

    ; 1. 現在のアクティブウィンドウが縮小・全画面化されている場合はそれを直接復元＆前面化
    if (hwnd && WindowStateMap.Has(key)) {
        RestoreWindow(hwnd)
        ActivateWindowSafely(hwnd)
        return
    }

    ; 2. アクティブウィンドウが未変更（デスクトップ・タスクバー、あるいは別の通常ウィンドウ）の場合:
    ;    LIFOスタック（ModifiedHistory）から直近の変更ウィンドウを探索してスマート復元＆前面化
    while (ModifiedHistory.Length > 0) {
        targetHwnd := ModifiedHistory[ModifiedHistory.Length]
        targetKey := String(targetHwnd)

        ; ウィンドウが既に閉じられているか、マップに存在しない場合はスタックから破棄して次へ
        if (!WinExist("ahk_id " targetHwnd) || !WindowStateMap.Has(targetKey)) {
            ModifiedHistory.Pop()
            continue
        }

        RestoreWindow(targetHwnd)
        ActivateWindowSafely(targetHwnd)
        return
    }

    ; 3. 対象が見つからない場合
    ShowFeedback("復元対象のウィンドウはありません")
}

RestoreWindow(hwnd) {
    global WindowStateMap
    key := String(hwnd)
    if !WindowStateMap.Has(key) {
        ShowFeedback("復元対象のウィンドウはありません")
        return
    }
    title := GetDisplayTitle(hwnd)
    saved := WindowStateMap[key]
    origW := saved.Has("w") ? saved["w"] : ""
    origH := saved.Has("h") ? saved["h"] : ""
    sizeInfo := (origW != "" && origH != "") ? " (" origW "x" origH ")" : ""

    if RestoreWindowState(hwnd)
        ShowFeedback("↩ 元のサイズに復元: " title sizeInfo)
    else
        ShowFeedback("⚠ 復元に失敗しました: " title)
}

; ============================================================
; すべての変更ウィンドウを一括復元 (トレイメニュー用 UX機能)
; ============================================================
RestoreAllWindows(showFeedback := true) {
    global WindowStateMap, ModifiedHistory
    count := 0
    hwnds := []
    for key, _ in WindowStateMap {
        hwnds.Push(Integer(key))
    }
    for _, hwnd in hwnds {
        if WinExist("ahk_id " hwnd) {
            if RestoreWindowState(hwnd)
                count++
        }
    }
    ModifiedHistory := []
    UpdateTrayMenuUI()

    if (showFeedback) {
        if (count > 0) {
            WriteLog("[RestoreAll] 一括復元完了: " count " 個のウィンドウを復元")
            ShowFeedback("↩ " String(count) " 個のウィンドウをすべて復元しました")
        } else {
            ShowFeedback("復元対象のウィンドウはありません")
        }
    } else {
        if (count > 0)
            WriteLog("[RestoreAll] 一括自動復元完了: " count " 個のウィンドウを復元")
    }
}

RestoreWindowState(hwnd) {
    global WindowStateMap

    key := String(hwnd)
    title := GetDisplayTitle(hwnd)

    if !WindowStateMap.Has(key) {
        try {
            DllCall("SetWindowRgn", "ptr", hwnd, "ptr", 0, "int", 1)
            WinRestore("ahk_id " hwnd)
        }
        return false
    }

    saved := WindowStateMap[key]

    try {
        ; 1. リージョンクリッピングを解除（ウィンドウ全体を再可視化）
        DllCall("SetWindowRgn", "ptr", hwnd, "ptr", 0, "int", 1)

        ; 2. スタイル復元（最大化ビット WS_MAXIMIZE = 0x01000000 を除いて適用）
        if saved.Has("style") {
            baseStyle := saved["style"] & ~0x01000000 ; WS_MAXIMIZE を除いた基本スタイル
            WinSetStyle(baseStyle, "ahk_id " hwnd)
        }
        if saved.Has("exStyle")
            WinSetExStyle(saved["exStyle"], "ahk_id " hwnd)

        ; ウィンドウの可視性を明示的に復帰
        try WinShow("ahk_id " hwnd)

        ; 3. 復元先座標のマルチモニター作業領域クランプ（画面外虚空への消失防止）
        rx := saved["x"], ry := saved["y"], rw := saved["w"], rh := saved["h"]
        EnsureWindowInScreenArea(&rx, &ry, &rw, &rh)

        ; 4. 位置・サイズ・フレーム変更をアトミック一括適用（チラつき撲滅）
        ;    元々の WS_EX_TOPMOST (0x0008) 属性に応じて HWND_TOPMOST (-1) / HWND_NOTOPMOST (-2) を厳密復元
        isTopMost := (saved.Has("exStyle") && (saved["exStyle"] & 0x0008))
        insertAfter := isTopMost ? -1 : -2
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", insertAfter, "int", rx, "int", ry, "int", rw, "int", rh, "uint", 0x0020) ; SWP_FRAMECHANGED

        ; 5. 最大化状態だった場合は正式に最大化へ遷移
        if (saved["minMax"] == 1)
            WinMaximize("ahk_id " hwnd)

        ; 6. Windows 11 の角丸設定をデフォルトに復帰
        SetWindowCornerPreference(hwnd, 0)

        ; 7. ウィンドウフレームの最終再描画通知
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0037)
        try WinRedraw("ahk_id " hwnd)

        WindowStateMap.Delete(key)
        RemoveFromHistory(hwnd)
        UpdateTrayMenuUI()

        PlayFeedbackSound("restore")
        WriteLog("[Restore] ウィンドウ状態復元完了: " title " (HWND: " hwnd ", Size: " rw "x" rh ")")
        return true
    } catch as err {
        WriteLog("[Error] 復元処理中に例外発生: " err.Message " (HWND: " hwnd ")", "ERROR")
        return false
    }
}

; ============================================================
; ウィンドウ状態保存（最大化時の通常座標もスクリーン座標系へ補正して退避）
; ============================================================
SaveWindowState(hwnd, mode := "custom") {
    global WindowStateMap

    key := String(hwnd)
    ; 既に保存済みの場合は上書きしない（元の状態を保持）
    if WindowStateMap.Has(key)
        return

    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        style := WinGetStyle("ahk_id " hwnd)
        exStyle := WinGetExStyle("ahk_id " hwnd)
        minMax := WinGetMinMax("ahk_id " hwnd)

        ; 最大化状態の場合は、元の通常座標（rcNormalPosition）の取得を試みる
        if (minMax != 0) {
            wp := Buffer(44, 0)
            NumPut("uint", 44, wp, 0)
            if DllCall("GetWindowPlacement", "ptr", hwnd, "ptr", wp, "int") {
                nl := NumGet(wp, 28, "int")
                nt := NumGet(wp, 32, "int")
                nr := NumGet(wp, 36, "int")
                nb := NumGet(wp, 40, "int")
                if (nr > nl && nb > nt) {
                    ; GetWindowPlacement の rcNormalPosition は、WS_EX_TOOLWINDOW がない通常ウィンドウでは
                    ; モニター作業領域を原点とするワークスペース座標系。
                    ; WS_EX_TOOLWINDOW (0x80) の場合はスクリーン座標系。
                    if (exStyle & 0x80) {
                        x := nl
                        y := nt
                    } else {
                        GetWindowWorkArea(hwnd, &mLeft, &mTop, &mRight, &mBottom)
                        x := nl + mLeft
                        y := nt + mTop
                    }
                    w := nr - nl
                    h := nb - nt
                }
            }
        }

        WindowStateMap[key] := Map(
            "x", x,
            "y", y,
            "w", w,
            "h", h,
            "style", style,
            "exStyle", exStyle,
            "minMax", minMax,
            "mode", mode
        )
    }
}

; ============================================================
; 閉じたウィンドウのクリーンアップ
; ============================================================
CleanupClosedWindows() {
    global WindowStateMap, ModifiedHistory
    keysToRemove := []
    for key, _ in WindowStateMap {
        hwnd := Integer(key)
        if !WinExist("ahk_id " hwnd)
            keysToRemove.Push(key)
    }
    for _, key in keysToRemove {
        hwnd := Integer(key)
        WindowStateMap.Delete(key)
        RemoveFromHistory(hwnd)
    }
    if (keysToRemove.Length > 0) {
        UpdateTrayMenuUI()
        WriteLog("[Cleanup] 終了済みウィンドウの登録解除: " keysToRemove.Length " 件")
    }
}
