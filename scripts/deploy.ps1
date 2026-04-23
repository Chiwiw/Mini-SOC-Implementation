# ============================================================
# deploy.ps1 - Windows PowerShell Deployment Script
# SOC Project | Infrastructure Builder
#
# CARA PAKAI:
#   .\scripts\deploy.ps1                  # Full deploy
#   .\scripts\deploy.ps1 -Step certs      # Hanya generate sertifikat
#   .\scripts\deploy.ps1 -Step start      # Hanya start stack
#   .\scripts\deploy.ps1 -Step status     # Cek status semua container
#   .\scripts\deploy.ps1 -Step stop       # Stop semua
#   .\scripts\deploy.ps1 -Step ngrok      # Start ngrok tunnel
#   .\scripts\deploy.ps1 -Step agent      # Cek status agent
# ============================================================

param(
    [ValidateSet("full", "certs", "start", "status", "stop", "ngrok", "agent", "logs", "restart")]
    [string]$Step = "full"
)

# ============================================================
# KONFIGURASI
# ============================================================
$ErrorActionPreference = "Continue"
$COMPOSE_FILE = "docker-compose.yml"
$DVWA_URL = "http://localhost:8080"
$DASHBOARD_URL = "https://localhost"

# ============================================================
# HELPER FUNCTIONS
# ============================================================
function Write-OK { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-FAIL { param($msg) Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-WARN { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-INFO { param($msg) Write-Host "  [i] $msg" -ForegroundColor Cyan }

function Write-Header {
    param($title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Blue
    Write-Host "  $title" -ForegroundColor Blue
    Write-Host "============================================================" -ForegroundColor Blue
}

function Write-Banner {
    Write-Host ""
    Write-Host "  ███╗   ███╗██╗███╗   ██╗██╗    ███████╗ ██████╗  ██████╗" -ForegroundColor Cyan
    Write-Host "  ████╗ ████║██║████╗  ██║██║    ██╔════╝██╔═══██╗██╔════╝" -ForegroundColor Cyan
    Write-Host "  ██╔████╔██║██║██╔██╗ ██║██║    ███████╗██║   ██║██║     " -ForegroundColor Cyan
    Write-Host "  ██║╚██╔╝██║██║██║╚██╗██║██║    ╚════██║██║   ██║██║     " -ForegroundColor Cyan
    Write-Host "  ██║ ╚═╝ ██║██║██║ ╚████║██║    ███████║╚██████╔╝╚██████╗" -ForegroundColor Cyan
    Write-Host "  ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝    ╚══════╝ ╚═════╝  ╚═════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Mini SOC Deployment Script | Windows PowerShell" -ForegroundColor Cyan
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================
# CHECK PREREQUISITES
# ============================================================
function Test-Prerequisites {
    Write-Header "CHECK PREREQUISITES"

    # Docker
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        Write-OK "Docker CLI tersedia"
        try {
            docker info 2>&1 | Out-Null
            Write-OK "Docker Desktop berjalan"
        } catch {
            Write-FAIL "Docker Desktop TIDAK berjalan! Buka Docker Desktop dulu."
            return $false
        }
    } else {
        Write-FAIL "Docker tidak terinstall! Download dari https://docker.com"
        return $false
    }

    # Docker Compose
    $composeVersion = docker compose version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Docker Compose: $composeVersion"
    } else {
        Write-FAIL "Docker Compose tidak tersedia!"
        return $false
    }

    # docker-compose.yml
    if (Test-Path $COMPOSE_FILE) {
        Write-OK "docker-compose.yml ditemukan"
    } else {
        Write-FAIL "docker-compose.yml tidak ditemukan di direktori ini!"
        Write-INFO "Pastikan kamu menjalankan script dari folder SOC-Project/"
        return $false
    }

    # .env
    if (Test-Path ".env") {
        Write-OK ".env file ditemukan"
    } else {
        Write-FAIL ".env file tidak ada!"
        Write-INFO "Buat file .env di root project dengan isi credentials."
        Write-INFO "Lihat INFRAS_README.md section 'Akses & Credentials' untuk template."
        return $false
    }

    # Buat direktori yang dibutuhkan
    if (-not (Test-Path "wazuh-logs")) {
        New-Item -ItemType Directory -Path "wazuh-logs" | Out-Null
        Write-OK "Direktori wazuh-logs dibuat"
    }
    if (-not (Test-Path "config\certs")) {
        New-Item -ItemType Directory -Path "config\certs" -Force | Out-Null
        Write-OK "Direktori config\certs dibuat"
    }

    return $true
}

# ============================================================
# GENERATE CERTIFICATES
# ============================================================
function Invoke-CertGeneration {
    Write-Header "GENERATE SSL CERTIFICATES"

    # Cek apakah sertifikat sudah ada
    if (Test-Path "config\certs\root-ca.pem") {
        Write-WARN "Sertifikat sudah ada di config\certs\"
        $answer = Read-Host "  Generate ulang? (y/N)"
        if ($answer -ne "y") {
            Write-INFO "Skip cert generation."
            return
        }
        # Hapus sertifikat lama
        Remove-Item "config\certs\*" -Force
    }

    Write-INFO "Menjalankan wazuh-certs-generator..."
    docker compose --profile setup up wazuh-certs-generator

    if (Test-Path "config\certs\root-ca.pem") {
        Write-OK "Sertifikat berhasil di-generate!"
        Write-INFO "Files:"
        Get-ChildItem "config\certs\*.pem" | ForEach-Object { Write-Host "    - $($_.Name)" }
    } else {
        Write-FAIL "Sertifikat GAGAL di-generate! Cek log di atas."
    }
}

# ============================================================
# START STACK
# ============================================================
function Start-Stack {
    Write-Header "STARTING SOC STACK"

    Write-INFO "Pulling Docker images (jika belum ada)..."
    docker compose pull 2>&1 | Out-Null

    Write-INFO "Building custom images (DVWA + Agent)..."
    docker compose build --no-cache dvwa 2>&1

    Write-INFO "Starting semua services..."
    docker compose up -d

    Write-Host ""
    Write-INFO "Menunggu services startup (estimasi 3-7 menit)..."
    Write-INFO "Monitor progress: docker compose logs -f"
    Write-Host ""

    # Tunggu dan cek health
    $services = @("wazuh-indexer", "wazuh-manager", "wazuh-dashboard", "dvwa-target")
    $timeout = 420  # 7 menit
    $elapsed = 0
    $interval = 15

    while ($elapsed -lt $timeout) {
        $allHealthy = $true
        foreach ($svc in $services) {
            $status = docker inspect --format='{{.State.Health.Status}}' $svc 2>&1
            if ($status -ne "healthy") {
                $allHealthy = $false
            }
        }

        if ($allHealthy) {
            Write-Host ""
            Write-OK "SEMUA SERVICES HEALTHY!"
            break
        }

        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $pct = [math]::Min(100, [math]::Round(($elapsed / $timeout) * 100))
        Write-Host "`r  [i] Menunggu... ($pct%%) - ${elapsed}s / ${timeout}s" -NoNewline -ForegroundColor Gray
    }

    if ($elapsed -ge $timeout) {
        Write-Host ""
        Write-WARN "Timeout! Beberapa services mungkin belum siap."
        Write-INFO "Cek manual: docker compose ps"
    }

    # Tampilkan status akhir
    Write-Host ""
    Get-ContainerStatus
}

# ============================================================
# CONTAINER STATUS
# ============================================================
function Get-ContainerStatus {
    Write-Header "CONTAINER STATUS"

    $containers = @("wazuh-indexer", "wazuh-manager", "wazuh-dashboard", "dvwa-target")

    foreach ($container in $containers) {
        try {
            $state = docker inspect --format='{{.State.Status}}' $container 2>&1
            $health = docker inspect --format='{{.State.Health.Status}}' $container 2>&1

            if ($state -eq "running") {
                if ($health -eq "healthy") {
                    Write-OK "$container : Running (healthy)"
                } elseif ($health -eq "starting") {
                    Write-WARN "$container : Running (starting...)"
                } else {
                    Write-FAIL "$container : Running ($health)"
                }
            } else {
                Write-FAIL "$container : $state"
            }
        } catch {
            Write-FAIL "$container : NOT FOUND"
        }
    }

    # Cek akses
    Write-Host ""
    Write-INFO "Akses Dashboard : https://localhost"
    Write-INFO "Akses DVWA      : http://localhost:8080"
    Write-INFO "Wazuh API       : http://localhost:55000"
}

# ============================================================
# CHECK AGENT
# ============================================================
function Get-AgentStatus {
    Write-Header "WAZUH AGENT STATUS"

    try {
        $result = docker exec wazuh-manager /var/ossec/bin/agent_control -lc 2>&1
        Write-Host $result
        Write-OK "Agent query selesai."
    } catch {
        Write-WARN "Tidak bisa query agent. Manager mungkin belum siap."
    }
}

# ============================================================
# STOP STACK
# ============================================================
function Stop-Stack {
    Write-Header "STOPPING SOC STACK"
    docker compose down
    Write-OK "Semua services dihentikan."
    Write-INFO "Data tetap aman di Docker volumes."
    Write-INFO "Untuk hapus data: docker compose down -v"
}

# ============================================================
# START NGROK
# ============================================================
function Start-Ngrok {
    Write-Header "NGROK TUNNEL"

    if (-not (Get-Command ngrok -ErrorAction SilentlyContinue)) {
        Write-FAIL "Ngrok tidak terinstall!"
        Write-INFO "Download dari: https://ngrok.com/download"
        Write-INFO "Atau install via: choco install ngrok  (jika pakai Chocolatey)"
        Write-INFO ""
        Write-INFO "Setelah install:"
        Write-INFO "  1. ngrok config add-authtoken YOUR_TOKEN"
        Write-INFO "  2. ngrok http 8080"
        return
    }

    # Cek apakah DVWA accessible
    try {
        $response = Invoke-WebRequest -Uri $DVWA_URL -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        Write-OK "DVWA accessible di $DVWA_URL"
    } catch {
        Write-FAIL "DVWA tidak accessible di $DVWA_URL!"
        Write-INFO "Pastikan stack sudah running: .\scripts\deploy.ps1 -Step start"
        return
    }

    Write-INFO "Starting Ngrok tunnel ke port 8080..."
    Write-INFO "Tekan Ctrl+C untuk stop tunnel."
    Write-INFO ""
    Write-Host "  >> Setelah ngrok jalan, catat URL-nya dan berikan ke Attacker!" -ForegroundColor Green
    Write-Host "  >> Monitor traffic: http://localhost:4040" -ForegroundColor Green
    Write-Host ""

    ngrok http 8080
}

# ============================================================
# SHOW LOGS
# ============================================================
function Show-Logs {
    Write-Header "LIVE LOGS"
    Write-INFO "Menampilkan log semua container (Ctrl+C untuk stop)..."
    docker compose logs -f --tail 50
}

# ============================================================
# RESTART STACK
# ============================================================
function Restart-Stack {
    Write-Header "RESTARTING SOC STACK"
    docker compose restart
    Start-Sleep -Seconds 5
    Get-ContainerStatus
}

# ============================================================
# FULL DEPLOY
# ============================================================
function Invoke-FullDeploy {
    Write-Banner

    # Step 1: Prerequisites
    $prereqOk = Test-Prerequisites
    if (-not $prereqOk) {
        Write-FAIL "Prerequisites check gagal! Perbaiki masalah di atas dulu."
        return
    }

    # Step 2: Certificates
    if (-not (Test-Path "config\certs\root-ca.pem")) {
        Invoke-CertGeneration
    } else {
        Write-INFO "Sertifikat sudah ada, skip generation."
    }

    # Step 3: Start
    Start-Stack

    # Step 4: Summary
    Write-Header "DEPLOYMENT SUMMARY"
    Write-Host ""
    Write-Host "  +-----------------------------------------------------+" -ForegroundColor Green
    Write-Host "  |  Dashboard SOC    : https://localhost               |" -ForegroundColor Green
    Write-Host "  |  User/Pass        : admin / WazuhSOC@2024!         |" -ForegroundColor Green
    Write-Host "  |                                                     |" -ForegroundColor Green
    Write-Host "  |  DVWA Target      : http://localhost:8080           |" -ForegroundColor Green
    Write-Host "  |  User/Pass        : admin / password               |" -ForegroundColor Green
    Write-Host "  |                                                     |" -ForegroundColor Green
    Write-Host "  |  Wazuh API        : http://localhost:55000          |" -ForegroundColor Green
    Write-Host "  +-----------------------------------------------------+" -ForegroundColor Green
    Write-Host ""
    Write-INFO "NEXT STEPS:"
    Write-INFO "  1. Buka Dashboard: https://localhost (accept SSL warning)"
    Write-INFO "  2. Verifikasi agent: Menu Agents > dvwa-target = Active"
    Write-INFO "  3. Start Ngrok:    .\scripts\deploy.ps1 -Step ngrok"
    Write-INFO "  4. Berikan URL Ngrok ke tim Attacker"
    Write-Host ""
}

# ============================================================
# MAIN - ROUTE STEP
# ============================================================
switch ($Step) {
    "full"    { Invoke-FullDeploy }
    "certs"   { Invoke-CertGeneration }
    "start"   { Start-Stack }
    "status"  { Write-Banner; Get-ContainerStatus }
    "stop"    { Stop-Stack }
    "ngrok"   { Start-Ngrok }
    "agent"   { Get-AgentStatus }
    "logs"    { Show-Logs }
    "restart" { Restart-Stack }
}
