@echo off
setlocal

echo.
echo Claude Code Session Forker - Installation Script
echo =================================================
echo.

REM Get the directory where this script is located
set "SCRIPT_DIR=%~dp0"

REM Set installation directory
set "INSTALL_DIR=%USERPROFILE%\.claude-menu"

echo Installing to: %INSTALL_DIR%
echo.

REM Create the installation directory if it doesn't exist
if not exist "%INSTALL_DIR%" (
    echo Creating directory: %INSTALL_DIR%
    mkdir "%INSTALL_DIR%"
    if errorlevel 1 (
        echo ERROR: Failed to create directory
        exit /b 1
    )
    echo Directory created successfully.
) else (
    echo Directory already exists.
)

echo.

REM Copy Claude-Menu.ps1 to the installation directory
if exist "%SCRIPT_DIR%Claude-Menu.ps1" (
    echo Copying Claude-Menu.ps1...
    copy /Y "%SCRIPT_DIR%Claude-Menu.ps1" "%INSTALL_DIR%\Claude-Menu.ps1" >nul
    if errorlevel 1 (
        echo ERROR: Failed to copy Claude-Menu.ps1
        exit /b 1
    )
    echo Claude-Menu.ps1 installed successfully!
) else (
    echo ERROR: Claude-Menu.ps1 not found in %SCRIPT_DIR%
    pause
    exit /b 1
)

echo.
echo Installation complete!
echo.
echo To use the script, run: fork
echo (Make sure fork.cmd is in your PATH or current directory)
echo.