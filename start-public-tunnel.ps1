$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$serverPidFile = Join-Path $scriptDir "public-server.pid"
$tunnelPidFile = Join-Path $scriptDir "public-tunnel.pid"
$serverOutLogFile = Join-Path $scriptDir "public-server.out.log"
$serverErrLogFile = Join-Path $scriptDir "public-server.err.log"
$tunnelOutLogFile = Join-Path $scriptDir "public-tunnel.out.log"
$tunnelErrLogFile = Join-Path $scriptDir "public-tunnel.err.log"
$shareNoteFile = Join-Path $scriptDir "PUBLIC_LINK.txt"

function Remove-FileIfExists([string]$path) {
  if (Test-Path $path) {
    Remove-Item $path -Force -ErrorAction SilentlyContinue
  }
}

function Stop-TrackedProcess([string]$pidPath) {
  if (-not (Test-Path $pidPath)) { return }
  try {
    $pid = Get-Content $pidPath -Raw
    if ($pid -match "^\d+$") {
      Stop-Process -Id ([int]$pid) -Force -ErrorAction SilentlyContinue
    }
  } catch {
  }
  Remove-FileIfExists $pidPath
}

function Ensure-Command([string]$name, [string]$hint) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "$name not found. $hint"
  }
}

function Resolve-CloudflaredPath() {
  $local = Join-Path $scriptDir "cloudflared.exe"
  if (Test-Path $local) { return $local }

  $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  Write-Host "[Setup] cloudflared not found. Downloading local binary..." -ForegroundColor Yellow
  $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
  Invoke-WebRequest -Uri $url -OutFile $local
  if (-not (Test-Path $local)) {
    throw "Failed to download cloudflared."
  }
  return $local
}

function Stop-ListeningProcessOnPort([int]$port) {
  try {
    $lines = netstat -ano | Select-String "LISTENING"
    $pids = @()
    foreach ($line in $lines) {
      $text = ($line.ToString() -replace "\s+", " ").Trim()
      if ($text -match "[:\.]$port ") {
        $parts = $text.Split(" ")
        $pid = $parts[$parts.Length - 1]
        if ($pid -match "^\d+$") {
          $pids += [int]$pid
        }
      }
    }
    $pids = $pids | Sort-Object -Unique
    foreach ($pid in $pids) {
      Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
      Write-Host "[Info] Stopped process on port $port (PID=$pid)"
    }
  } catch {
  }
}

function Is-PortListening([int]$port) {
  try {
    $line = netstat -ano | Select-String "LISTENING" | Where-Object { $_.ToString() -match "[:\.]$port " } | Select-Object -First 1
    return $null -ne $line
  } catch {
    return $false
  }
}

function Wait-LocalServer([string]$apiKey) {
  $headers = @{ Authorization = "Bearer $apiKey" }
  for ($i = 1; $i -le 40; $i++) {
    try {
      $r = Invoke-RestMethod -Uri "http://localhost:7860/status" -Headers $headers -Method GET -TimeoutSec 4
      if ($null -ne $r) { return $r }
    } catch {
    }
    Start-Sleep -Milliseconds 500
  }
  throw "Local proxy did not become ready on port 7860."
}

function Wait-LocalServerNoAuth() {
  for ($i = 1; $i -le 30; $i++) {
    try {
      $r = Invoke-RestMethod -Uri "http://localhost:7860/status" -Method GET -TimeoutSec 4
      if ($null -ne $r) { return $r }
    } catch {
    }
    Start-Sleep -Milliseconds 500
  }
  throw "Existing server on port 7860 is not responding at /status."
}

function Wait-TryCloudflareUrl() {
  for ($i = 1; $i -le 80; $i++) {
    $combined = ""
    if (Test-Path $tunnelOutLogFile) {
      $combined += (Get-Content $tunnelOutLogFile -Raw -ErrorAction SilentlyContinue) + "`n"
    }
    if (Test-Path $tunnelErrLogFile) {
      $combined += (Get-Content $tunnelErrLogFile -Raw -ErrorAction SilentlyContinue) + "`n"
    }
    if ($combined) {
      $match = [regex]::Match($combined, "https://[a-z0-9-]+\.trycloudflare\.com/?")
      if ($match.Success) {
        return $match.Value.TrimEnd("/")
      }
    }
    if ($i % 2 -eq 0) {
      Write-Host "[Info] Waiting for trycloudflare URL..." -ForegroundColor DarkGray
    }
    Start-Sleep -Milliseconds 500
  }
  throw "Failed to obtain trycloudflare URL."
}

function Wait-PublicCheck([string]$baseUrl, [string]$apiKey) {
  $headers = @{ Authorization = "Bearer $apiKey" }
  for ($i = 1; $i -le 30; $i++) {
    try {
      $r = Invoke-RestMethod -Uri "$baseUrl/status" -Headers $headers -Method GET -TimeoutSec 6
      if ($null -ne $r) { return $true }
    } catch {
    }
    Start-Sleep -Seconds 1
  }
  return $false
}

try {
  Write-Host ""
  Write-Host "========================================"
  Write-Host "  ChatGPT Proxy - Public Share Start"
  Write-Host "========================================"
  Write-Host ""

  Ensure-Command "node" "Install Node.js LTS from https://nodejs.org"
  $cloudflaredPath = Resolve-CloudflaredPath

  Remove-FileIfExists $tunnelOutLogFile
  Remove-FileIfExists $tunnelErrLogFile
  Remove-FileIfExists $serverOutLogFile
  Remove-FileIfExists $serverErrLogFile
  Remove-FileIfExists $shareNoteFile
  Stop-TrackedProcess $tunnelPidFile

  $startedServer = $false
  $serverProc = $null
  $apiKey = ""

  if (Is-PortListening 7860) {
    Write-Host "[Info] Port 7860 already in use. Reusing existing local server." -ForegroundColor Yellow
    $apiKey = "dummy"
    $localStatus = Wait-LocalServerNoAuth
  } else {
    Stop-TrackedProcess $serverPidFile
    Stop-ListeningProcessOnPort 7860

    $apiKey = ("share-" + [guid]::NewGuid().ToString("N"))
    Write-Host "[Info] One-time API key generated." -ForegroundColor Cyan

    $startCmd = "set PROXY_API_KEY=$apiKey&& node server.mjs"
    $serverProc = Start-Process -FilePath "cmd.exe" `
      -ArgumentList "/c", $startCmd `
      -WorkingDirectory $scriptDir `
      -RedirectStandardOutput $serverOutLogFile `
      -RedirectStandardError $serverErrLogFile `
      -PassThru
    [System.IO.File]::WriteAllText($serverPidFile, "$($serverProc.Id)")
    Write-Host "[Info] Local proxy started. PID=$($serverProc.Id)"

    try {
      $localStatus = Wait-LocalServer -apiKey $apiKey
      if (-not $localStatus.authenticated) {
        throw "Not authenticated yet. Run 2_인증.bat first."
      }
      $startedServer = $true
    } catch {
      $isAddrInUse = $false
      if (Test-Path $serverErrLogFile) {
        $isAddrInUse = [bool](Select-String -Path $serverErrLogFile -Pattern "EADDRINUSE" -SimpleMatch -ErrorAction SilentlyContinue)
      }
      if ($isAddrInUse) {
        Write-Host "[Warn] Port 7860 is already in use. Switching to existing server mode." -ForegroundColor Yellow
        Stop-TrackedProcess $serverPidFile
        $apiKey = "dummy"
        $localStatus = Wait-LocalServerNoAuth
        $startedServer = $false
      } else {
        throw
      }
    }
  }
  Write-Host "[Info] Local proxy health check passed."

  $tunnelProc = Start-Process -FilePath $cloudflaredPath `
    -ArgumentList "tunnel --config NUL --url http://localhost:7860 --no-autoupdate" `
    -WorkingDirectory $scriptDir `
    -RedirectStandardOutput $tunnelOutLogFile `
    -RedirectStandardError $tunnelErrLogFile `
    -PassThru
  [System.IO.File]::WriteAllText($tunnelPidFile, "$($tunnelProc.Id)")
  Write-Host "[Info] cloudflared started. PID=$($tunnelProc.Id)"

  $publicBase = Wait-TryCloudflareUrl
  Write-Host "[Info] Tunnel URL found: $publicBase" -ForegroundColor Cyan

  $note = @"
ChatGPT Proxy Public Share (Quick Tunnel)
=========================================
API Endpoint (RisuAI): $publicBase/v1
API Key: $apiKey
Model example: gpt-4o

Quick test URL:
$publicBase/status

Important:
- Keep this window open while sharing.
- URL changes every time you restart.
- To stop sharing, run 5_stop_public_share.bat
"@
  Set-Content -Path $shareNoteFile -Value $note -Encoding UTF8
  Write-Host "[Info] Share file created: $shareNoteFile"

  $publicOk = Wait-PublicCheck -baseUrl $publicBase -apiKey $apiKey
  if (-not $publicOk) {
    Write-Host "[Warn] Public /status check failed now. URL may still become reachable in 10-30s." -ForegroundColor Yellow
  }

  try {
    Set-Clipboard -Value $publicBase
  } catch {
  }

  Write-Host ""
  Write-Host "[OK] Public share is ready." -ForegroundColor Green
  Write-Host "URL: $publicBase/v1" -ForegroundColor Green
  Write-Host "API Key: $apiKey" -ForegroundColor Green
  Write-Host ""
  Write-Host "Saved: $shareNoteFile"
  Write-Host ""

  Start-Process notepad.exe $shareNoteFile | Out-Null

  Write-Host "Press Ctrl+C to stop both server and tunnel."
  while ($true) {
    Start-Sleep -Seconds 2
    if ($startedServer -and $serverProc -and $serverProc.HasExited) { throw "Local proxy process exited unexpectedly." }
    if ($tunnelProc.HasExited) { throw "cloudflared process exited unexpectedly." }
  }
}
catch {
  Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
  if (Test-Path $serverErrLogFile) {
    Write-Host ""
    Write-Host "[server stderr tail]" -ForegroundColor Yellow
    Get-Content $serverErrLogFile -Tail 40 | ForEach-Object { Write-Host $_ }
  }
  if (Test-Path $serverOutLogFile) {
    Write-Host ""
    Write-Host "[server stdout tail]" -ForegroundColor Yellow
    Get-Content $serverOutLogFile -Tail 40 | ForEach-Object { Write-Host $_ }
  }
  if (Test-Path $tunnelErrLogFile) {
    Write-Host ""
    Write-Host "[cloudflared stderr tail]" -ForegroundColor Yellow
    Get-Content $tunnelErrLogFile -Tail 40 | ForEach-Object { Write-Host $_ }
  }
  if (Test-Path $tunnelOutLogFile) {
    Write-Host ""
    Write-Host "[cloudflared stdout tail]" -ForegroundColor Yellow
    Get-Content $tunnelOutLogFile -Tail 40 | ForEach-Object { Write-Host $_ }
  }
  throw
}
finally {
  Stop-TrackedProcess $tunnelPidFile
  if ($startedServer) {
    Stop-TrackedProcess $serverPidFile
  }
}
