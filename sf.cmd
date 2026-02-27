@echo off
if not exist "%USERPROFILE%\.claude-menu\Claude-Menu.ps1" echo Session Forge not installed.
if not exist "%USERPROFILE%\.claude-menu\Claude-Menu.ps1" echo https://sys1000.net
if not exist "%USERPROFILE%\.claude-menu\Claude-Menu.ps1" goto :EOF
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%USERPROFILE%\.claude-menu\Claude-Menu.ps1"
