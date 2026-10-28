@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1"
if errorlevel 1 (
    echo Uninstall failed. Close the application and retry.
    pause
    exit /b 1
)
echo Uninstall complete. Any additional user files were retained.
pause
