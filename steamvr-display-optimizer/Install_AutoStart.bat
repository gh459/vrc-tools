@echo off
title SteamVR Display Optimizer - Auto Start Setup
chcp 65001 > nul
cd /d "%~dp0"
echo =====================================================
echo  SteamVR Display Optimizer - Auto Start Setup
echo =====================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SteamVR_DisplayOptimizer.ps1" -InstallStartup
echo.
pause
