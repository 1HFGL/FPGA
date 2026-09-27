@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_modelsim.ps1"
exit /b %ERRORLEVEL%