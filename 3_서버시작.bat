@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo.
echo ========================================
echo   ChatGPT Proxy - Server Start
echo ========================================
echo.
echo Close this window to stop the server.
echo Press Ctrl+C anytime to stop.
echo.

:ASK_INTERVAL
set "RESTART_MIN="
set /p RESTART_MIN=Restart every how many minutes? (default 60): 

if not defined RESTART_MIN set "RESTART_MIN=60"
for /f "delims=0123456789" %%A in ("%RESTART_MIN%") do set "RESTART_MIN="
if not defined RESTART_MIN goto ASK_INTERVAL
if %RESTART_MIN% LEQ 0 goto ASK_INTERVAL

set /a WAIT_SEC=%RESTART_MIN%*60
set "PID_FILE=%~dp0server.pid"

echo.
echo Auto-restart interval: %RESTART_MIN% minute(s)
echo.

:LOOP
if exist "%PID_FILE%" del /q "%PID_FILE%" >nul 2>&1

echo ========================================
echo [%date% %time%] Starting server...
echo ========================================

powershell -NoProfile -Command "$p=Start-Process -FilePath 'node' -ArgumentList 'server.mjs' -WorkingDirectory '%~dp0' -PassThru; [System.IO.File]::WriteAllText('%PID_FILE%',$p.Id)"

if not exist "%PID_FILE%" (
  echo Failed to start server. Retrying in 10 seconds...
  timeout /t 10 /nobreak >nul
  goto LOOP
)

set /p NODE_PID=<"%PID_FILE%"
if "%NODE_PID%"=="" (
  echo Failed to get PID. Retrying in 10 seconds...
  timeout /t 10 /nobreak >nul
  goto LOOP
)

echo Running PID: %NODE_PID%
echo Restarting in %RESTART_MIN% minute(s)...

timeout /t %WAIT_SEC% /nobreak >nul

echo.
echo [%date% %time%] Restarting server...
taskkill /PID %NODE_PID% /T /F >nul 2>&1

goto LOOP
