# privatecodexproxy Linux 초보자 가이드

이 문서는 Linux(특히 Google Cloud Ubuntu VM)에서  
컴퓨터를 잘 모르는 분도 그대로 따라 할 수 있게 만든 안내입니다.

Windows의 이 3단계를 Linux에서도 똑같이 씁니다.
- `1_설치.bat` -> `1_설치.sh`
- `2_인증.bat` -> `2_인증.sh`
- `4_start_public_share.bat` -> `4_start_public_share.sh`

## 1) 진짜 처음부터: 필수 준비물 설치

아래 명령은 Ubuntu VM에서 그대로 복붙하면 됩니다.

```bash
sudo apt update
sudo apt install -y git curl ca-certificates gnupg
```

Node.js(LTS) 설치:

```bash
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs
```

설치 확인:

```bash
node -v
npm -v
git --version
curl --version
```

버전 숫자가 나오면 정상입니다.

## 2) 프로젝트 받기 (한 줄)

아래 한 줄 실행:

```bash
curl -fsSL https://raw.githubusercontent.com/LUNARIA1/privatecodexproxy/linuxver/bootstrap_linux.sh | bash
```

완료되면 폴더 이동:

```bash
cd privatecodexproxy
```

## 3) 실행 권한 부여 (한 번만)

```bash
chmod +x ./*.sh
```

## 4) 1단계 설치

```bash
./1_설치.sh
```

## 5) 2단계 인증

```bash
./2_인증.sh
```

중요:
- 데스크톱 Linux면 브라우저 인증 창이 열립니다.
- GCP SSH처럼 화면이 없는 서버면 자동으로 `device auth` 모드로 바뀝니다.
- 터미널에 나오는 URL/코드를 휴대폰 또는 내 PC 브라우저에서 입력해 인증하세요.

## 6) 4단계 공개 공유 시작

```bash
./4_start_public_share.sh
```

성공하면 `PUBLIC_LINK.txt` 파일이 생깁니다.  
그 안의 값을 RisuAI에 넣으세요:

- URL: `https://...trycloudflare.com/v1`
- API Key: `share-...`

주의:
- 공유 중에는 터미널 창을 닫지 마세요.
- URL은 실행할 때마다 바뀝니다.

## 7) 공유 종료

```bash
./5_stop_public_share.sh
```

## 가장 많이 막히는 문제

`sudo: command not found`
- Ubuntu가 아닌 다른 배포판일 수 있습니다. (Debian/Ubuntu 기준 문서)

`node: command not found`
- Node.js 설치가 안 된 상태입니다. 위 1단계 Node.js 설치부터 다시 실행하세요.

`Permission denied`
- `chmod +x ./*.sh`를 먼저 실행하세요.

`Auth failed`
- `./2_인증.sh`를 다시 실행하세요.
- 그래도 안 되면 `tokens.json` 삭제 후 재시도:
```bash
rm -f tokens.json
./2_인증.sh
```

`4_start_public_share.sh`가 바로 종료됨
- 잠시 후 다시 실행하세요.
- 네트워크 정책/방화벽이 강한 환경이면 Cloudflare quick tunnel 연결이 지연될 수 있습니다.

