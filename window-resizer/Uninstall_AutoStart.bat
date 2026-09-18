@echo off
setlocal
cd /d "%~dp0"

echo =====================================================
echo   Window Resizer - Remove Auto-Start Setup
echo =====================================================
echo.

:: Check for Administrator privileges using net session
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [INFO] Requesting Administrator privileges to remove Task Scheduler task...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo [1/3] Removing Task Scheduler task...
schtasks /Query /TN "WindowResizer" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    schtasks /Delete /TN "WindowResizer" /F >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        echo   -^> [SUCCESS] Task Scheduler logon task deleted.
    ) else (
        echo   -^> [WARNING] Failed to delete Task Scheduler task.
    )
) else (
    echo   -^> Task was not registered in Task Scheduler.
)

echo.
echo [2/3] Checking and removing Startup folder shortcut...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$lnk = [Environment]::GetFolderPath('Startup') + '\WindowResizer.lnk'; if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host '  -> [SUCCESS] Removed shortcut from Startup folder.' } else { Write-Host '  -> No shortcut found in Startup folder.' }"

echo.
echo [3/3] Stopping running WindowResizer process...
tasklist /FI "IMAGENAME eq WindowResizer.exe" 2>nul | find /I "WindowResizer.exe" >nul
if %ERRORLEVEL% equ 0 (
    echo   -^> Requesting graceful shutdown to restore any shrunk windows...
    taskkill /IM WindowResizer.exe >nul 2>&1
    timeout /t 1 /nobreak >nul
    tasklist /FI "IMAGENAME eq WindowResizer.exe" 2>nul | find /I "WindowResizer.exe" >nul
    if %ERRORLEVEL% equ 0 (
        taskkill /F /IM WindowResizer.exe >nul 2>&1
    )
    echo   -^> [SUCCESS] Process stopped safely.
) else (
    echo   -^> No running WindowResizer process detected.
)

echo.
echo =====================================================
echo  [SUCCESS] Auto-start configuration removed.
echo  Window Resizer will no longer start automatically.
echo =====================================================
echo.
pause
exit /b 0