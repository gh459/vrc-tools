@echo off
title SteamVR Display Optimizer - Remove Auto Start
chcp 65001 > nul
cd /d "%~dp0"
echo =====================================================
echo  SteamVR Display Optimizer - Remove Auto Start
echo =====================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SteamVR_DisplayOptimizer.ps1" -UninstallStartup
echo.
pause
