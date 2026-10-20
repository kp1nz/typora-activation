@echo off
setlocal
cd /d "%~dp0"
title Typora Activation

rem ---- locate a PowerShell host ----
set "PS=powershell.exe"
where pwsh.exe >nul 2>nul && set "PS=pwsh.exe"

if not exist "%~dp0activate.ps1" (
  echo [x] activate.ps1 not found next to this script.
  pause
  exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0activate.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (echo Done.) else (echo Finished with code %RC%.)
pause
exit /b %RC%
