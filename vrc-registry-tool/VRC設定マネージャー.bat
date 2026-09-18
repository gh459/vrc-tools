@echo off
title VRChat 設定マネージャー
chcp 65001 > nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VRC設定インポート＆エクスポート.ps1"
echo.
pause
