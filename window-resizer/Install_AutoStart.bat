@echo off
setlocal
cd /d "%~dp0"

echo =====================================================
echo   Window Resizer - Auto-Start Setup (Logon Task)
echo =====================================================
echo.

:: Check for Administrator privileges using net session
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [INFO] Requesting Administrator privileges for Task Scheduler registration...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

set "EXE_PATH=%~dp0WindowResizer.exe"

:: Check if WindowResizer.exe exists, build if missing
if not exist "%EXE_PATH%" (
    echo [INFO] WindowResizer.exe not found. Building now...
    call "%~dp0build.bat"
    if not exist "%EXE_PATH%" (
        echo [ERROR] Failed to build WindowResizer.exe.
        echo.
        pause
        exit /b 1
    )
)

echo [1/2] Registering Task Scheduler logon task (Silent with Highest privileges)...
schtasks /Create /TN "WindowResizer" /TR "\"%EXE_PATH%\"" /SC ONLOGON /RL HIGHEST /F >nul 2>&1

if %ERRORLEVEL% equ 0 (
    echo   -^> [SUCCESS] Task Scheduler registration succeeded.
    :: Optimize task settings: Allow running on batteries, prevent timeout
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ts = Get-ScheduledTask -TaskName 'WindowResizer' -ErrorAction SilentlyContinue; if ($ts) { $ts.Settings.DisallowStartIfOnBatteries = $false; $ts.Settings.StopIfGoingOnBatteries = $false; $ts.Settings.ExecutionTimeLimit = 'PT0S'; Set-ScheduledTask -TaskName 'WindowResizer' -Settings $ts.Settings >$null 2>&1 }"
    :: Remove legacy startup shortcut to prevent duplicate launches
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$lnk = [Environment]::GetFolderPath('Startup') + '\WindowResizer.lnk'; if (Test-Path $lnk) { Remove-Item $lnk -Force }" >nul 2>&1
) else (
    echo   -^> [WARNING] Task Scheduler registration failed (Error: %ERRORLEVEL%).
    echo   -^> Creating fallback shortcut in Startup folder...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([Environment]::GetFolderPath('Startup') + '\WindowResizer.lnk'); $s.TargetPath = '%EXE_PATH%'; $s.WorkingDirectory = '%~dp0'; $s.Description = 'Window Resizer'; $s.Save()"
    echo   -^> [SUCCESS] Fallback shortcut created in Startup folder.
)

echo.
echo [2/2] Checking running process...
tasklist /FI "IMAGENAME eq WindowResizer.exe" 2>nul | find /I "WindowResizer.exe" >nul
if %ERRORLEVEL% equ 0 (
    echo   -^> WindowResizer is already running in background.
) else (
    echo   -^> Starting WindowResizer now...
    start "" "%EXE_PATH%"
    echo   -^> Started successfully.
)

echo.
echo =====================================================
echo  [SUCCESS] Auto-Start registration complete!
echo  Window Resizer will automatically start on logon
echo  with highest privileges without any UAC prompts.
echo =====================================================
echo.
pause
exit /b 0