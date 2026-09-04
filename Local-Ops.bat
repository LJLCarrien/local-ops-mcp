@echo off
setlocal

cd /d "%~dp0"

if not exist "%~dp0scripts\launcher.ps1" (
    echo Local Ops launcher was not found:
    echo   %~dp0scripts\launcher.ps1
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\launcher.ps1"
exit /b %errorlevel%
