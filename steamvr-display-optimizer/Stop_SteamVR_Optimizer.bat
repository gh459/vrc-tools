@echo off
title SteamVR Display Optimizer - Stop
chcp 65001 > nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SteamVR_DisplayOptimizer.ps1" -Stop
pause
