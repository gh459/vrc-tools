@echo off
title VRChat 設定インポート
chcp 65001 > nul
cd /d "%~dp0"
echo =====================================================
echo  VRChat 設定インポート
echo =====================================================
echo.
echo [注意] %%USERPROFILE%%\Downloads\vrchat-settings.reg の内容をレジストリへ取り込みます。
echo (実行前に既存設定のバックアップ vrchat-settings-backup.reg がダウンロードフォルダに自動生成されます)
echo.
set /p CONFIRM="インポートを実行しますか？ (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    echo キャンセルしました。
    pause
    exit /b 0
)

echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VRC設定インポート.ps1"
echo.
echo [完了] インポートが完了しました。
echo.
pause
