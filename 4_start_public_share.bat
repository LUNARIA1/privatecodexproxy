@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo.
echo ========================================
echo   ChatGPT Proxy - Public Share
echo ========================================
echo.
echo This starts:
echo   1) local proxy server (port 7860)
echo   2) free Cloudflare quick tunnel
echo.
echo Keep this window open while sharing.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-public-tunnel.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
  echo [ERROR] Public share stopped with error. Code=%EXIT_CODE%
) else (
  echo [OK] Public share stopped.
)
echo.
pause
exit /b %EXIT_CODE%
