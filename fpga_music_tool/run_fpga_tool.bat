@echo off
setlocal
set "MPLCONFIGDIR=%LOCALAPPDATA%\fpga_music_tool_cache"
if not exist "%MPLCONFIGDIR%" mkdir "%MPLCONFIGDIR%"
start "" "D:\python\pythonw.exe" "%~dp0main.py"
exit /b 0