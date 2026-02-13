@echo off
chcp 65001 >nul
echo.
echo ========================================
echo   ChatGPT Proxy - 초기 설치
echo ========================================
echo.
echo Node.js가 필요합니다. 설치 안 되어 있으면:
echo   https://nodejs.org 에서 LTS 버전 설치
echo.
echo 의존성 설치 중...
call npm install
echo.
if %ERRORLEVEL% NEQ 0 (
    echo [에러] npm install 실패! Node.js가 설치되어 있는지 확인하세요.
    pause
    exit /b 1
)
echo ✅ 설치 완료!
echo.
echo 이제 "2_인증.bat" 을 실행하세요.
echo.
pause
