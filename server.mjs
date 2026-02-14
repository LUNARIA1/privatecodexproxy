/**
 * ChatGPT OAuth Proxy Server for RisuAI
 * =======================================
 * Based on analysis of opencode's codex.ts
 * 
 * This proxy:
 * 1. Authenticates via OpenAI's OAuth 2.0 PKCE flow (same as opencode/Codex CLI)
 * 2. Rewrites API calls to chatgpt.com's backend Codex endpoint
 * 3. Adds required headers (originator, ChatGPT-Account-Id, User-Agent)
 * 4. Auto-refreshes expired tokens
 * 5. Exposes OpenAI-compatible /v1/chat/completions for RisuAI
 */

import http from 'node:http';
import { URL, URLSearchParams } from 'node:url';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ==================== Constants (from opencode codex.ts) ====================
const CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann";
const ISSUER = "https://auth.openai.com";
const CODEX_API_ENDPOINT = "https://chatgpt.com/backend-api/codex/responses";
const OAUTH_PORT = 1455;         // OAuth callback port (same as opencode)
const PROXY_PORT = 7860;         // Proxy server port for RisuAI
const TOKEN_FILE = path.join(__dirname, "tokens.json");
const VERSION = "1.0.0";
const REQUIRED_API_KEY = (process.env.PROXY_API_KEY || "").trim();

// ==================== PKCE Helpers ====================
function generateRandomString(length) {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
  const bytes = crypto.randomBytes(length);
  return Array.from(bytes).map(b => chars[b % chars.length]).join("");
}

function base64UrlEncode(buffer) {
  return Buffer.from(buffer)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function generatePKCE() {
  const verifier = generateRandomString(43);
  const hash = crypto.createHash("sha256").update(verifier).digest();
  const challenge = base64UrlEncode(hash);
  return { verifier, challenge };
}

function generateState() {
  return base64UrlEncode(crypto.randomBytes(32));
}

// ==================== JWT Parsing ====================
function parseJwtClaims(token) {
  const parts = token.split(".");
  if (parts.length !== 3) return undefined;
  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString());
  } catch {
    return undefined;
  }
}

function extractAccountId(tokens) {
  for (const tokenField of ["id_token", "access_token"]) {
    if (!tokens[tokenField]) continue;
    const claims = parseJwtClaims(tokens[tokenField]);
    if (!claims) continue;
    const id =
      claims.chatgpt_account_id ||
      claims?.["https://api.openai.com/auth"]?.chatgpt_account_id ||
      claims?.organizations?.[0]?.id;
    if (id) return id;
  }
  return undefined;
}

// ==================== Token Storage ====================
function loadTokens() {
  try {
    return JSON.parse(fs.readFileSync(TOKEN_FILE, "utf-8"));
  } catch {
    return null;
  }
}

function saveTokens(tokens) {
  fs.writeFileSync(TOKEN_FILE, JSON.stringify(tokens, null, 2), { mode: 0o600 });
}

// ==================== OAuth Token Exchange & Refresh ====================
async function exchangeCodeForTokens(code, redirectUri, pkce) {
  const response = await fetch(`${ISSUER}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectUri,
      client_id: CLIENT_ID,
      code_verifier: pkce.verifier,
    }).toString(),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Token exchange failed (${response.status}): ${text}`);
  }
  return response.json();
}

async function refreshAccessToken(refreshToken) {
  console.log("[Token] Refreshing access token...");
  const response = await fetch(`${ISSUER}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
      client_id: CLIENT_ID,
    }).toString(),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Token refresh failed (${response.status}): ${text}`);
  }
  const tokens = await response.json();
  console.log("[Token] Access token refreshed successfully!");
  return tokens;
}

// ==================== Ensure valid access token ====================
async function getValidAccessToken() {
  let stored = loadTokens();
  if (!stored) {
    throw new Error("Not authenticated. Run with --auth-only first or visit http://localhost:" + PROXY_PORT + "/auth");
  }

  // Check if token needs refresh (expired or within 60s of expiring)
  if (!stored.access_token || stored.expires_at < Date.now() + 60_000) {
    const newTokens = await refreshAccessToken(stored.refresh_token);
    const accountId = extractAccountId(newTokens) || stored.account_id;
    stored = {
      access_token: newTokens.access_token,
      refresh_token: newTokens.refresh_token,
      expires_at: Date.now() + (newTokens.expires_in ?? 3600) * 1000,
      account_id: accountId,
    };
    saveTokens(stored);
  }

  return stored;
}

// ==================== OAuth Flow ====================
async function startOAuthFlow() {
  const pkce = await generatePKCE();
  const state = generateState();
  const redirectUri = `http://localhost:${OAUTH_PORT}/auth/callback`;

  const params = new URLSearchParams({
    response_type: "code",
    client_id: CLIENT_ID,
    redirect_uri: redirectUri,
    scope: "openid profile email offline_access",
    code_challenge: pkce.challenge,
    code_challenge_method: "S256",
    id_token_add_organizations: "true",
    codex_cli_simplified_flow: "true",
    state,
    originator: "opencode",
  });
  const authUrl = `${ISSUER}/oauth/authorize?${params.toString()}`;

  return new Promise((resolve, reject) => {
    const server = http.createServer(async (req, res) => {
      const url = new URL(req.url, `http://localhost:${OAUTH_PORT}`);

      if (url.pathname === "/auth/callback") {
        const code = url.searchParams.get("code");
        const returnedState = url.searchParams.get("state");
        const error = url.searchParams.get("error");

        if (error) {
          res.writeHead(400, { "Content-Type": "text/html; charset=utf-8" });
          res.end(`<h1>인증 실패</h1><p>${url.searchParams.get("error_description") || error}</p>`);
          server.close();
          reject(new Error(error));
          return;
        }

        if (returnedState !== state) {
          res.writeHead(400, { "Content-Type": "text/html; charset=utf-8" });
          res.end("<h1>State mismatch - CSRF 공격 의심</h1>");
          server.close();
          reject(new Error("State mismatch"));
          return;
        }

        try {
          const tokens = await exchangeCodeForTokens(code, redirectUri, pkce);
          const accountId = extractAccountId(tokens);
          const stored = {
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_at: Date.now() + (tokens.expires_in ?? 3600) * 1000,
            account_id: accountId,
          };
          saveTokens(stored);

          res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
          res.end(`
            <!DOCTYPE html>
            <html>
            <head><title>인증 성공!</title></head>
            <body style="font-family:system-ui;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#131010;color:#f1ecec;">
              <div style="text-align:center;padding:2rem;">
                <h1 style="color:#4ade80;">✅ 인증 성공!</h1>
                <p style="color:#b7b1b1;">이 창을 닫아도 됩니다. 프록시 서버가 실행 중입니다.</p>
                <p style="color:#b7b1b1;">Account ID: ${accountId || "(없음)"}</p>
              </div>
              <script>setTimeout(() => window.close(), 3000);</script>
            </body>
            </html>
          `);
          server.close();
          resolve(stored);
        } catch (err) {
          res.writeHead(500, { "Content-Type": "text/html; charset=utf-8" });
          res.end(`<h1>토큰 교환 실패</h1><p>${err.message}</p>`);
          server.close();
          reject(err);
        }
      } else {
        res.writeHead(404);
        res.end("Not found");
      }
    });

    server.listen(OAUTH_PORT, () => {
      console.log(`\n[OAuth] 콜백 서버 시작됨: http://localhost:${OAUTH_PORT}`);
      console.log(`\n${"=".repeat(60)}`);
      console.log("  아래 URL을 브라우저에서 열어 ChatGPT 계정으로 로그인하세요:");
      console.log(`  ${authUrl}`);
      console.log(`${"=".repeat(60)}\n`);

      // 자동으로 브라우저 열기
      import("open").then(m => m.default(authUrl)).catch(() => {
        console.log("  (브라우저가 자동으로 열리지 않으면 위 URL을 수동으로 복사하세요)");
      });
    });

    server.on("error", reject);

    // 5분 타임아웃
    setTimeout(() => {
      server.close();
      reject(new Error("OAuth 타임아웃 (5분 초과)"));
    }, 5 * 60 * 1000);
  });
}

// ==================== Device Code Flow (Headless) ====================
async function startDeviceCodeFlow() {
  console.log("\n[Device Auth] 디바이스 코드 인증 시작...");

  const deviceResponse = await fetch(`${ISSUER}/api/accounts/deviceauth/usercode`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "User-Agent": `chatgpt-proxy/${VERSION}`,
    },
    body: JSON.stringify({ client_id: CLIENT_ID }),
  });

  if (!deviceResponse.ok) {
    throw new Error(`디바이스 인증 초기화 실패: ${deviceResponse.status}`);
  }

  const deviceData = await deviceResponse.json();
  const interval = Math.max(parseInt(deviceData.interval) || 5, 1) * 1000 + 3000;

  console.log(`\n${"=".repeat(60)}`);
  console.log(`  아래 URL에 접속해서 코드를 입력하세요:`);
  console.log(`  URL: ${ISSUER}/codex/device`);
  console.log(`  코드: ${deviceData.user_code}`);
  console.log(`${"=".repeat(60)}\n`);

  // 자동으로 브라우저 열기
  import("open").then(m => m.default(`${ISSUER}/codex/device`)).catch(() => { });

  // Polling
  while (true) {
    const response = await fetch(`${ISSUER}/api/accounts/deviceauth/token`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "User-Agent": `chatgpt-proxy/${VERSION}`,
      },
      body: JSON.stringify({
        device_auth_id: deviceData.device_auth_id,
        user_code: deviceData.user_code,
      }),
    });

    if (response.ok) {
      const data = await response.json();

      // Exchange authorization code for tokens
      const tokenResponse = await fetch(`${ISSUER}/oauth/token`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          grant_type: "authorization_code",
          code: data.authorization_code,
          redirect_uri: `${ISSUER}/deviceauth/callback`,
          client_id: CLIENT_ID,
          code_verifier: data.code_verifier,
        }).toString(),
      });

      if (!tokenResponse.ok) {
        throw new Error(`Token exchange failed: ${tokenResponse.status}`);
      }

      const tokens = await tokenResponse.json();
      const accountId = extractAccountId(tokens);
      const stored = {
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        expires_at: Date.now() + (tokens.expires_in ?? 3600) * 1000,
        account_id: accountId,
      };
      saveTokens(stored);
      console.log("\n[Device Auth] ✅ 인증 성공!");
      console.log(`  Account ID: ${accountId || "(없음)"}`);
      return stored;
    }

    if (response.status !== 403 && response.status !== 404) {
      throw new Error(`디바이스 인증 실패: ${response.status}`);
    }

    process.stdout.write(".");
    await new Promise(r => setTimeout(r, interval));
  }
}

// ==================== Read Request Body ====================
function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", c => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

// ==================== Proxy Server ====================
async function startProxyServer() {
  const server = http.createServer(async (req, res) => {
    // CORS
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "*");

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    const url = new URL(req.url, `http://localhost:${PROXY_PORT}`);

    // Optional inbound API key guard for public exposure.
    // Enabled only when PROXY_API_KEY env var is set.
    if (REQUIRED_API_KEY && url.pathname !== "/auth") {
      const authHeader = req.headers["authorization"] || "";
      const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : authHeader;
      if (bearer !== REQUIRED_API_KEY) {
        res.writeHead(401, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          error: {
            message: "Unauthorized",
            type: "auth_error",
            code: "invalid_api_key",
          }
        }));
        return;
      }
    }

    // 모든 요청 로깅 (디버깅용)
    console.log(`[${new Date().toISOString()}] ${req.method} ${url.pathname}`);

    // === Auth page ===
    if (url.pathname === "/auth") {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      const hasTokens = !!loadTokens();
      res.end(`
        <!DOCTYPE html>
        <html>
        <head><title>ChatGPT Proxy Auth</title></head>
        <body style="font-family:system-ui;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#131010;color:#f1ecec;">
          <div style="text-align:center;padding:2rem;max-width:500px;">
            <h1>ChatGPT Proxy Server</h1>
            <p style="color:${hasTokens ? '#4ade80' : '#ef4444'};">
              토큰 상태: ${hasTokens ? '✅ 인증됨' : '❌ 미인증'}
            </p>
            <p style="color:#b7b1b1;">터미널에서 <code>node server.mjs --auth-only</code> 실행하여 인증하세요.</p>
            <h2 style="margin-top:2rem;">RisuAI 설정</h2>
            <div style="background:#1e1e1e;padding:1rem;border-radius:8px;text-align:left;font-family:monospace;font-size:14px;">
              <p>URL: <span style="color:#4ade80;">http://localhost:${PROXY_PORT}/v1</span></p>
              <p>API Key: <span style="color:#4ade80;">dummy</span> (아무값이나 OK)</p>
              <p>Model: <span style="color:#4ade80;">gpt-4o</span></p>
            </div>
          </div>
        </body>
        </html>
      `);
      return;
    }

    // === Status check ===
    if (url.pathname === "/status") {
      const tokens = loadTokens();
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        authenticated: !!tokens,
        account_id: tokens?.account_id,
        token_expires: tokens?.expires_at ? new Date(tokens.expires_at).toISOString() : null,
      }));
      return;
    }

    // === Models endpoint (for RisuAI compatibility) ===
    // 다양한 경로 패턴 지원: /models, /v1/models 등
    if (url.pathname.endsWith("/models") || url.pathname.endsWith("/models/")) {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        object: "list",
        data: [
          { id: "gpt-4o", object: "model", owned_by: "openai" },
          { id: "gpt-4o-mini", object: "model", owned_by: "openai" },
          { id: "o4-mini", object: "model", owned_by: "openai" },
          { id: "gpt-4.1", object: "model", owned_by: "openai" },
          { id: "gpt-4.1-mini", object: "model", owned_by: "openai" },
          { id: "gpt-4.1-nano", object: "model", owned_by: "openai" },
        ],
      }));
      return;
    }

    // === Chat completions proxy ===
    // RisuAI는 설정에 따라 다양한 경로로 보냄:
    //   /v1/chat/completions, /chat/completions, 또는 URL 그대로
    // 그래서 POST 요청이면 전부 chat completions로 처리 (catch-all)
    const isCompletions = url.pathname.includes("completions") || url.pathname.includes("responses");
    if (req.method === "POST" && (isCompletions || !["/auth", "/status"].includes(url.pathname))) {
      try {
        const auth = await getValidAccessToken();
        const body = await readBody(req);
        const parsed = JSON.parse(body.toString());

        const clientWantsStream = !!parsed.stream;
        console.log(`[Proxy] ${new Date().toISOString()} | model: ${parsed.model} | client_stream: ${clientWantsStream}`);

        // OpenAI Chat Completions → Codex Responses API 변환
        // Codex API는 stream: true를 강제하므로 항상 true로 보냄
        const codexBody = convertToResponsesFormat(parsed);

        const headers = {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${auth.access_token}`,
          "User-Agent": `chatgpt-proxy/${VERSION} (${process.platform} ${process.arch})`,
          "originator": "opencode",
        };

        if (auth.account_id) {
          headers["ChatGPT-Account-Id"] = auth.account_id;
        }

        const codexResponse = await fetch(CODEX_API_ENDPOINT, {
          method: "POST",
          headers,
          body: JSON.stringify(codexBody),
        });

        if (!codexResponse.ok) {
          const errText = await codexResponse.text();
          console.error(`[Proxy] Codex API error (${codexResponse.status}):`, errText);
          res.writeHead(codexResponse.status, { "Content-Type": "application/json" });
          res.end(JSON.stringify({
            error: {
              message: `Codex API error: ${errText}`,
              type: "proxy_error",
              code: codexResponse.status,
            }
          }));
          return;
        }

        // Codex API는 항상 stream으로 응답함
        // 클라이언트가 stream 원하면 → SSE로 전달
        // 클라이언트가 stream 안 원하면 → 스트림 모아서 JSON 반환

        const reader = codexResponse.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";
        let fullContent = "";
        let responseId = `chatcmpl-${Date.now()}`;

        if (clientWantsStream) {
          res.writeHead(200, {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
          });
        }

        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split("\n");
            buffer = lines.pop() || "";

            for (const line of lines) {
              if (!line.trim()) continue;

              if (line.startsWith("event: ")) continue;

              if (line.startsWith("data: ")) {
                const data = line.slice(6);
                if (data === "[DONE]") {
                  if (clientWantsStream) res.write("data: [DONE]\n\n");
                  continue;
                }
                try {
                  const event = JSON.parse(data);
                  if (event.id) responseId = event.id;
                  const converted = convertResponseEventToCompletion(event, parsed.model);
                  if (converted) {
                    // 텍스트 누적 (비-스트리밍용)
                    const delta = converted.choices?.[0]?.delta?.content;
                    if (delta) fullContent += delta;

                    if (clientWantsStream) {
                      res.write(`data: ${JSON.stringify(converted)}\n\n`);
                    }
                  }
                } catch {
                  if (clientWantsStream) res.write(line + "\n\n");
                }
              }
            }
          }
        } catch (streamErr) {
          console.error("[Proxy] Stream error:", streamErr.message);
        }

        if (clientWantsStream) {
          res.end();
        } else {
          // 스트림에서 모은 텍스트를 Chat Completions 포맷으로 반환
          console.log(`[Proxy] Non-stream response collected: ${fullContent.length} chars`);
          const result = {
            id: responseId,
            object: "chat.completion",
            created: Math.floor(Date.now() / 1000),
            model: parsed.model,
            choices: [{
              index: 0,
              message: { role: "assistant", content: fullContent },
              finish_reason: "stop",
            }],
            usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
          };
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(JSON.stringify(result));
        }
      } catch (err) {
        console.error("[Proxy] Error:", err.message);
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          error: {
            message: err.message,
            type: "proxy_error",
          }
        }));
      }
      return;
    }

    // === Fallback (GET 등 처리 안 되는 요청) ===
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      status: "ok",
      message: "ChatGPT Proxy Server is running. POST to any path for chat completions.",
      endpoints: {
        chat: "POST /v1/chat/completions",
        models: "GET /v1/models",
        status: "GET /status",
        auth: "GET /auth",
      }
    }));
  });

  // LAN IP 자동 감지
  const nets = (await import('node:os')).networkInterfaces();
  let lanIP = "localhost";
  for (const ifaces of Object.values(nets)) {
    for (const iface of ifaces || []) {
      if (iface.family === "IPv4" && !iface.internal) {
        lanIP = iface.address;
        break;
      }
    }
    if (lanIP !== "localhost") break;
  }

  server.listen(PROXY_PORT, "0.0.0.0", () => {
    console.log(`\n${"=".repeat(60)}`);
    console.log("  🚀 ChatGPT Proxy Server 시작!");
    console.log(`  로컬 URL:    http://localhost:${PROXY_PORT}/v1`);
    console.log(`  LAN URL:     http://${lanIP}:${PROXY_PORT}/v1`);
    console.log(`  상태 확인:   http://localhost:${PROXY_PORT}/status`);
    console.log(`  인증 페이지: http://localhost:${PROXY_PORT}/auth`);
    console.log(`${"=".repeat(60)}\n`);
    console.log("  📌 같은 PC에서 RisuAI, SillyTavern 사용:");
    console.log(`     URL:    http://localhost:${PROXY_PORT}/v1\n`);
    console.log("  📱 모바일/다른 기기에서 RisuAI 사용:");
    console.log(`     URL:    http://${lanIP}:${PROXY_PORT}/v1`);
    console.log("     (같은 Wi-Fi에 연결되어 있어야 합니다)\n");
    console.log("     API Key: dummy (아무값이나 OK)");
    console.log("     Model:  gpt-5.1, gpt-5.2 등\n");
  });
}

// ==================== Format Converters ====================

/**
 * OpenAI Chat Completions 포맷 → Codex Responses API 포맷 변환
 * 
 * Chat Completions:
 *   { model, messages: [{role:"system", content:...}, {role:"user", content:...}] }
 * 
 * Responses API (Codex가 요구하는 포맷):
 *   { model, instructions: "system prompt", input: [{role:"user", content:...}] }
 * 
 * system 메시지 → instructions 필드
 * user/assistant 메시지 → input 배열
 */
function convertToResponsesFormat(chatCompletionReq) {
  const messages = chatCompletionReq.messages || [];

  // system 메시지를 instructions로 추출
  const systemMessages = messages.filter(m => m.role === "system");
  const nonSystemMessages = messages.filter(m => m.role !== "system");

  // system 메시지들을 하나의 instructions 문자열로 합침
  const instructions = systemMessages
    .map(m => typeof m.content === "string" ? m.content : JSON.stringify(m.content))
    .join("\n\n") || "You are a helpful assistant.";

  // input 메시지 변환 (user, assistant만)
  const input = nonSystemMessages.map(m => {
    // content가 배열인 경우 (multimodal) 등 그대로 전달
    return {
      role: m.role,
      content: m.content,
    };
  });

  // Codex endpoint는 제한적인 파라미터만 허용
  // 허용: model, instructions, input, stream, store
  // 비허용: temperature, max_tokens, max_output_tokens, top_p, 
  //         frequency_penalty, presence_penalty, logit_bias 등
  // → RisuAI가 보내는 추가 파라미터는 전부 무시
  const body = {
    model: chatCompletionReq.model || "gpt-4o",
    instructions: instructions,
    input: input,
    stream: true,   // Codex API는 stream: true 필수
    store: false,   // Codex API는 store: false 필수
  };

  // 무시된 파라미터 로깅 (디버깅용)
  const ignored = [];
  for (const key of ['temperature', 'max_tokens', 'max_output_tokens', 'max_completion_tokens', 'top_p', 'frequency_penalty', 'presence_penalty', 'logit_bias', 'seed']) {
    if (chatCompletionReq[key] !== undefined) ignored.push(key);
  }
  if (ignored.length > 0) {
    console.log(`[Proxy] Ignored unsupported params: ${ignored.join(', ')}`);
  }

  console.log(`[Proxy] Converted: ${messages.length} messages → instructions(${instructions.length}chars) + ${input.length} input msgs`);

  return body;
}

/**
 * Codex Responses API 결과 → Chat Completions 포맷 변환 (non-stream)
 */
function convertResponseToCompletion(responseData, model) {
  // 만약 이미 Chat Completions 포맷이면 그대로 반환
  if (responseData.choices) return responseData;

  // Responses API 포맷에서 변환
  const content = responseData.output?.map(item => {
    if (item.type === "message") {
      return item.content?.map(c => c.text || "").join("") || "";
    }
    return "";
  }).join("") || responseData.output_text || "";

  return {
    id: responseData.id || `chatcmpl-${Date.now()}`,
    object: "chat.completion",
    created: Math.floor(Date.now() / 1000),
    model: model,
    choices: [{
      index: 0,
      message: {
        role: "assistant",
        content: content,
      },
      finish_reason: responseData.status === "completed" ? "stop" : "stop",
    }],
    usage: responseData.usage || { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
  };
}

/**
 * Codex Responses API SSE 이벤트 → Chat Completions SSE 이벤트 변환
 */
function convertResponseEventToCompletion(event, model) {
  // 이미 Chat Completions 스트림 포맷이면 그대로 반환
  if (event.choices) return event;

  // Responses API의 다양한 이벤트 타입 처리
  if (event.type === "response.output_text.delta") {
    return {
      id: event.response_id || `chatcmpl-${Date.now()}`,
      object: "chat.completion.chunk",
      created: Math.floor(Date.now() / 1000),
      model: model,
      choices: [{
        index: 0,
        delta: {
          content: event.delta || "",
        },
        finish_reason: null,
      }],
    };
  }

  if (event.type === "response.output_text.done" || event.type === "response.completed" || event.type === "response.done") {
    return {
      id: event.response_id || `chatcmpl-${Date.now()}`,
      object: "chat.completion.chunk",
      created: Math.floor(Date.now() / 1000),
      model: model,
      choices: [{
        index: 0,
        delta: {},
        finish_reason: "stop",
      }],
    };
  }

  // response.content_part.delta (일부 모델에서 사용)
  if (event.type === "response.content_part.delta" && event.delta?.text) {
    return {
      id: event.response_id || `chatcmpl-${Date.now()}`,
      object: "chat.completion.chunk",
      created: Math.floor(Date.now() / 1000),
      model: model,
      choices: [{
        index: 0,
        delta: {
          content: event.delta.text,
        },
        finish_reason: null,
      }],
    };
  }

  // 기타 이벤트는 무시 (response.created, response.in_progress 등)
  return null;
}

// ==================== Main ====================
async function main() {
  const args = process.argv.slice(2);
  const authOnly = args.includes("--auth-only");
  const deviceAuth = args.includes("--device");

  console.log("\n🔮 ChatGPT OAuth Proxy Server (based on opencode codex.ts analysis)");
  console.log("━".repeat(60));

  const existingTokens = loadTokens();

  if (authOnly || !existingTokens) {
    if (!existingTokens) {
      console.log("\n[!] 토큰이 없습니다. 먼저 인증이 필요합니다.");
    }

    if (deviceAuth) {
      await startDeviceCodeFlow();
    } else {
      await startOAuthFlow();
    }

    if (authOnly) {
      console.log("\n✅ 인증 완료! 이제 `node server.mjs`로 프록시 서버를 시작하세요.");
      process.exit(0);
    }
  } else {
    console.log("\n✅ 기존 토큰 발견.");
    if (existingTokens.expires_at) {
      const expiresIn = Math.round((existingTokens.expires_at - Date.now()) / 1000);
      if (expiresIn > 0) {
        console.log(`   토큰 만료까지: ${Math.floor(expiresIn / 60)}분 ${expiresIn % 60}초`);
      } else {
        console.log("   토큰 만료됨 - 다음 요청 시 자동 갱신됩니다.");
      }
    }
  }

  startProxyServer();
}

main().catch(err => {
  console.error("\n❌ 에러:", err.message);
  process.exit(1);
});
