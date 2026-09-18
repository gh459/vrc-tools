@echo off
title SteamVR Display Optimizer
chcp 65001 > nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%~dp0SteamVR_DisplayOptimizer.ps1"
pause
