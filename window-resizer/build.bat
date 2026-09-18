@echo off
setlocal
cd /d "%~dp0"

echo =====================================================
echo   Window Resizer v2.4 - Build ^& Compile
echo =====================================================
echo.

set "AHK2EXE="
if exist "%LOCALAPPDATA%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=%LOCALAPPDATA%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
if not defined AHK2EXE if exist "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe"
if not defined AHK2EXE if exist "C:\Users\kull\AppData\Local\Programs\AutoHotkey\Compiler\Ahk2Exe.exe" set "AHK2EXE=C:\Users\kull\AppData\Local\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"

if not defined AHK2EXE (
    echo [ERROR] Ahk2Exe.exe compiler was not found.
    goto :FAIL
)

set "AHK_BASE="
if exist "%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_BASE=%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
if not defined AHK_BASE if exist "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_BASE=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not defined AHK_BASE if exist "C:\Users\kull\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_BASE=C:\Users\kull\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe"

if not defined AHK_BASE (
    echo [ERROR] AutoHotkey64.exe base binary was not found.
    goto :FAIL
)

set "WAS_RUNNING=0"
tasklist /FI "IMAGENAME eq WindowResizer.exe" 2>nul | find /I "WindowResizer.exe" >nul
if %ERRORLEVEL% equ 0 (
    set "WAS_RUNNING=1"
    echo [INFO] Stopping running WindowResizer...
    powershell -NoProfile -Command "Start-Process taskkill -ArgumentList '/F /IM WindowResizer.exe' -Verb RunAs -Wait" >nul 2>&1
    timeout /t 1 /nobreak >nul
)

echo [COMPILING] WindowResizer.ahk -^> WindowResizer.exe...
start /wait "" "%AHK2EXE%" /in "WindowResizer.ahk" /out "WindowResizer.exe" /base "%AHK_BASE%" /silent

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Compilation failed with error code %ERRORLEVEL%.
    goto :FAIL
)

echo [SUCCESS] WindowResizer.exe compiled successfully.
if "%WAS_RUNNING%"=="1" (
    echo [INFO] Restarting WindowResizer.exe...
    start "" "%~dp0WindowResizer.exe"
)

echo.
pause
exit /b 0

:FAIL
echo.
pause
exit /b 1
