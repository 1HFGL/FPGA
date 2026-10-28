@echo off
setlocal
start "" /wait "%~dp0app\JingzouStudio.exe" --self-check "%~dp0selfcheck.json"
if errorlevel 1 (
    echo Self-check failed. See selfcheck.json.
    pause
    exit /b 1
)
echo Self-check passed. See selfcheck.json.
pause
