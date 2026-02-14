# 먀달(https://m.cafe.daum.net/subdued20club/VrjL/959264) 전용 배포입니다!

---

# 🔮 ChatGPT → RisuAI 프록시 서버

> ChatGPT Plus/Pro 구독자라면, **별도 API 결제 없이** RisuAI에서 GPT-4o, GPT-5.2 등을 쓸 수 있습니다.

---

## 📋 준비물

- ✅ **ChatGPT Plus 또는 Pro 구독** (월 $20/$200)
- ✅ **Node.js** (무료) — [https://nodejs.org](https://nodejs.org) 에서 **LTS** 버전 설치
- ✅ **RisuAI** (로컬 구동 버전)

---

## 🚀 사용법 (3단계!)

### 1️⃣ 설치 (최초 1회)

**`1_설치.bat`** 을 더블클릭하세요.

> Node.js가 안 깔려있으면 [https://nodejs.org](https://nodejs.org) 에서 LTS 버전 먼저 설치!
> 설치 후 컴퓨터 **재부팅** 하면 확실합니다.

---

### 2️⃣ 인증 (최초 1회)

**`2_인증.bat`** 을 더블클릭하세요.

1. 브라우저가 자동으로 열립니다
2. ChatGPT 계정으로 **로그인**
3. "허용" 클릭
4. 터미널에 **✅ 인증 성공!** 이 뜨면 완료

> 💡 이 과정은 **한 번만** 하면 됩니다!
> 나중에 토큰이 만료되면 이 단계를 다시 하면 됩니다.

---

### 3️⃣ 서버 시작 (매번)

**`3_서버시작.bat`** 을 더블클릭하세요.

이런 화면이 뜨면 성공:
```
🚀 ChatGPT Proxy Server 시작!
  로컬 URL:    http://localhost:7860/v1
  LAN URL:     http://192.168.x.x:7860/v1
```

> ⚠️ **이 창을 끄면 안 됩니다!** RisuAI 쓰는 동안 계속 켜두세요.

---

### 4️⃣ RisuAI 설정

| 설정 항목 | 값 |
|-----------|---|
| **URL** | `http://localhost:7860/v1` |
| **API Key** | `dummy` (아무 글자나 OK) |
| **Model** | `gpt-5.1` (추천) |

#### 📱 모바일에서 쓰려면?

같은 Wi-Fi에 연결된 상태에서, URL을 서버 시작 시 표시되는 **LAN URL**로 변경:
```
http://192.168.x.x:7860/v1
```
(x.x는 서버 시작할 때 터미널에 표시되는 숫자를 쓰세요)

> 안 되면 Windows 방화벽 문제일 수 있습니다.
> 관리자 PowerShell에서: `netsh advfirewall firewall add rule name="ChatGPT Proxy" dir=in action=allow protocol=TCP localport=7860`

---

## 🎮 사용 가능한 모델

| 모델 | 특징 |
|------|------|
| `gpt-5` |   |
| `gpt-5.1` | 추천 |
| `gpt-5.1-codex` |   |
| `gpt-5.1-codex-max` |   |
| `gpt-5.1-codex-mini` |   |
| `gpt-5.2` | 최신 |
| `gpt-5.2-codex` | 최신 |

---

## ❓ FAQ

**Q: 추가 요금이 나오나요?**
A: 아닙니다! ChatGPT 구독에 포함된 기능을 사용합니다.

**Q: temperature, max_tokens 설정이 안 돼요**
A: 정상입니다. 이 엔드포인트는 해당 파라미터를 지원하지 않습니다. 

**Q: "Token refresh failed" 에러**
A: `tokens.json` 파일을 삭제하고, `2_인증.bat` 다시 실행하세요.

**Q: "usage_not_included" 에러**
A: ChatGPT **Plus 이상** 구독이 필요합니다. 무료 계정은 안 됩니다.

**Q: Mac/Linux에서도 되나요?**
A: 네! Node.js 설치 후 터미널에서 `npm install` → `node server.mjs --auth-only` → `node server.mjs`

---

## ⚠️ 주의사항

- 🔒 **`tokens.json`을 절대 공유하지 마세요** (계정 도용 위험!)
- 📌 OpenAI 내부 엔드포인트를 사용하므로 **언제든 막힐 수 있습니다**
- 🚫 과도한 사용(봇, 대량 요청)은 계정 정지 사유
- 💡 개인 용도로만 사용하세요

---

## 📁 파일 설명

| 파일 | 설명 |
|------|------|
| `1_설치.bat` | 최초 1회 실행 (의존성 설치) |
| `2_인증.bat` | ChatGPT 계정 인증 |
| `3_서버시작.bat` | 프록시 서버 시작 |
| `server.mjs` | 프록시 서버 본체 (수정 X) |
| `package.json` | 프로젝트 설정 (수정 X) |
| `tokens.json` | 인증 토큰 (자동 생성, 🔒공유 금지!) |
| `README.md` | 이 문서 |



