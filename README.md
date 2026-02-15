# 먀달(https://m.cafe.daum.net/subdued20club/VrjL/959264) 전용 배포입니다!

---

# privatecodexproxy Linux Guide 

Google Cloud Ubuntu VM 기준으로, 복붙으로 실행할 수 있게 정리했습니다.

## 목표

Windows에서 하던 이 순서를 Linux에서도 그대로 사용합니다.
- `1_설치.bat` -> `1_설치.sh`
- `2_인증.bat` -> `2_인증.sh`
- `4_start_public_share.bat` -> `4_start_public_share.sh`

그리고 추가로:
- `6_백그라운드시작.sh` -> `screen`으로 백그라운드 실행 (SSH 종료/내 PC 종료 후에도 유지)
- `7_백그라운드중지.sh` -> 백그라운드 중지
- `8_백그라운드상태.sh` -> 상태 확인

## 1) 필수 프로그램 설치 (처음 1번만)

아래를 그대로 실행하세요.

```bash
sudo apt update
sudo apt install -y git curl ca-certificates gnupg
```

Node.js LTS 설치:

```bash
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs
```

확인:

```bash
node -v
npm -v
git --version
curl --version
```

## 2) 프로젝트 받기

```bash
curl -fsSL https://raw.githubusercontent.com/LUNARIA1/privatecodexproxy/linuxver/bootstrap_linux.sh | bash
```

```bash
cd privatecodexproxy
chmod +x ./*.sh
```

## 3) 기본 설정

```bash
./1_설치.sh
./2_인증.sh
```

인증 참고:
- 데스크톱 환경이면 브라우저가 열립니다.
- GCP SSH처럼 화면이 없는 환경이면 자동으로 device auth 모드가 켜집니다.
- 즉시 보이는 URL `https://auth.openai.com/codex/device` 에 접속해서, 터미널에 나온 코드를 입력하면 됩니다.

## 4) 실행 방법 2가지

### A. 일반 실행 (터미널 열어둬야 함. 컴퓨터 못 끔)

```bash
./4_start_public_share.sh
```

### B. 백그라운드 실행 (이것을 권장, 닫고 컴퓨터 꺼도 유지)

```bash
./6_백그라운드시작.sh
```

성공하면 `PUBLIC_LINK.txt`에 아래 정보가 저장됩니다.
- URL: `https://xxxx.trycloudflare.com/v1`
- API Key: `share-xxxx`

## 5) 백그라운드 관리

상태 확인:

```bash
./8_백그라운드상태.sh
```

중지:

```bash
./7_백그라운드중지.sh
```

screen 세션 직접 보기:

```bash
screen -r privatecodexproxy_share
```

분리(detach):
- `Ctrl + A` 누르고 `D`

## 6) 주의사항

- VM(구글 클라우드 인스턴스) 자체를 중지하면 서버도 중지됩니다.
- 공유 URL은 서버를 재시작할 때마다 변경됩니다.
- `tokens.json`은 절대 공유하지 마세요.

## 7) 문제 해결

`Permission denied`

```bash
chmod +x ./*.sh
```

`node: command not found`
- Node.js 설치가 안 된 상태입니다. 1단계 다시 실행하세요.

인증 실패 시:

```bash
rm -f tokens.json
./2_인증.sh
```

백그라운드 실행이 안 될 때:

```bash
./8_백그라운드상태.sh
tail -n 50 screen-public-share.log
```
