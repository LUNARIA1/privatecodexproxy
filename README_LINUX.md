# oauth_proxy Linux Guide

Google Cloud VM(Ubuntu) 같은 Linux 환경에서, Windows의 아래 순서를 그대로 사용할 수 있게 만든 안내입니다.

- `1_설치.bat` -> `1_install.sh`
- `2_인증.bat` -> `2_auth.sh`
- `4_start_public_share.bat` -> `4_start_public_share.sh`

## 0) 필수 준비

- Node.js LTS
- git
- curl

Ubuntu/Debian 예시:

```bash
sudo apt update
sudo apt install -y git curl
```

Node.js가 없다면 먼저 설치하세요: https://nodejs.org

## 1) 가장 쉬운 설치(curl 1줄)

`bootstrap_linux.sh`를 원격에서 바로 실행하는 방식입니다.

```bash
curl -fsSL https://raw.githubusercontent.com/LUNARIA1/privatecodexproxy/linuxver/bootstrap_linux.sh | bash
```

실행 후:

```bash
cd oauth_proxy
./1_install.sh
./2_auth.sh
./4_start_public_share.sh
```

## 2) 일반 설치(git clone)

```bash
git clone https://github.com/REPLACE_WITH_YOUR_ID/oauth_proxy.git
cd oauth_proxy
chmod +x ./*.sh
./1_install.sh
./2_auth.sh
./4_start_public_share.sh
```

## 3) 종료

공유 중지:

```bash
./5_stop_public_share.sh
```

## 파일 매핑

- `1_install.sh`: 의존성 설치 (`npm install`)
- `2_auth.sh`: OAuth 인증
- `3_start_server.sh`: 로컬 서버 자동 재시작 실행
- `4_start_public_share.sh`: 서버 + Cloudflare Quick Tunnel 시작
- `5_stop_public_share.sh`: 공개 공유 중지
- `start-public-tunnel.sh`: 공개 공유 내부 실행 스크립트

## 참고

- `4_start_public_share.sh` 실행 후 `PUBLIC_LINK.txt`가 생성됩니다.
- URL은 실행할 때마다 바뀝니다.
- `cloudflared`가 없으면 스크립트가 현재 폴더에 자동 다운로드합니다.
