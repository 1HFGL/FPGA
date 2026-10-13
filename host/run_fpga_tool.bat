@echo off
setlocal
set "MPLCONFIGDIR=%LOCALAPPDATA%\fpga_music_tool_cache"
if not exist "%MPLCONFIGDIR%" mkdir "%MPLCONFIGDIR%"
set "TOOL_PYTHON=%~dp0..\.venv-studio\Scripts\python.exe"
if not exist "%TOOL_PYTHON%" (
    echo Project Python environment is missing. See host/README.md.
    pause
    exit /b 1
)
rem Keep the console visible when optional legacy-tool dependencies are missing.
"%TOOL_PYTHON%" "%~dp0main.py"
if errorlevel 1 (
    echo Legacy console requires the dependencies listed in host/requirements.txt.
    pause
    exit /b 1
)
exit /b 0
