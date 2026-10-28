@echo off
setlocal
set "STUDIO_PYTHON=%~dp0..\.venv-studio\Scripts\pythonw.exe"
if not exist "%STUDIO_PYTHON%" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_studio.ps1"
    if errorlevel 1 exit /b 1
)
start "" "%STUDIO_PYTHON%" "%~dp0studio.py" --demo
