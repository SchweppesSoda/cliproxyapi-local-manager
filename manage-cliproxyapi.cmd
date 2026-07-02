@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\windows\manage-cliproxyapi.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
if "%~1"=="" (
  echo.
  pause
)
exit /b %EXIT_CODE%

