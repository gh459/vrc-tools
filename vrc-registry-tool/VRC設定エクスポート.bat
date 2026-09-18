@echo off
title VRChat 設定エクスポート
chcp 65001 > nul
cd /d "%~dp0"
echo =====================================================
echo  VRChat 設定エクスポート
echo =====================================================
echo HKCU\Software\VRChat\vrchat の設定をダウンロードフォルダへ書き出します...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VRC設定エクスポート.ps1"
echo.
echo [完了] %%USERPROFILE%%\Downloads\vrchat-settings.reg に保存されました。
echo.
pause
