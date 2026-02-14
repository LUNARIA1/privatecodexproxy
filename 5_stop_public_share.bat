@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

echo.
echo ========================================
echo   ChatGPT Proxy - Stop Public Share
echo ========================================
echo.

for %%F in (public-tunnel.pid public-server.pid) do (
  if exist "%%F" (
    set /p PID=<"%%F"
    if not "!PID!"=="" (
      taskkill /PID !PID! /T /F >nul 2>&1
      echo Stopped PID !PID! from %%F
    )
    del /q "%%F" >nul 2>&1
  )
)

echo Done.
echo.
pause
