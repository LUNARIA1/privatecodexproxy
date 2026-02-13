@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo.
echo ========================================
echo   ChatGPT Proxy - Auth
echo ========================================
echo.
echo A browser will open. Sign in to your ChatGPT account.
echo.

set "AUTH_LOG=%~dp0auth_result.log"
if exist "%AUTH_LOG%" del /q "%AUTH_LOG%" >nul 2>&1

node server.mjs --auth-only > "%AUTH_LOG%" 2>&1
set "AUTH_EXIT=%ERRORLEVEL%"

type "%AUTH_LOG%"
echo.

findstr /C:"node server.mjs" "%AUTH_LOG%" >nul
if not errorlevel 1 goto AUTH_OK

if not "%AUTH_EXIT%"=="0" echo [ERROR] Auth failed. Please try again.
if "%AUTH_EXIT%"=="0" echo [INFO] Auth command finished. Check logs above.
pause
exit /b %AUTH_EXIT%

:AUTH_OK
echo [OK] Auth success detected.
pause
exit /b 0
