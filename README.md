# Mini SOC Project Implementation
**Role:** Infrastructure SOC Engineer | **Status:** Core Infrastructure Ready 🚀
**GitHub Repo:** [Chiwiw/Mini-SOC-Implementation](https://github.com/Chiwiw/Mini-SOC-Implementation)

---

## INFRASTRUCTURE SUMMARY
Sebagai **Infrastructure SOC Engineer**, kami telah membangun dan menstabilkan stack SIEM berbasis Wazuh dengan target DVWA. Berikut adalah ringkasan pekerjaan yang telah diselesaikan:

1.  **Container Stabilization**: Memperbaiki issue startup pada `wazuh-manager` dan `dvwa-target`.
2.  **Rule Refactoring**: Mengoptimalkan `local_rules.xml` dan `custom_decoders.xml` menggunakan syntax **PCRE2** modern untuk mencegah crash pada `wazuh-analysisd`.
3.  **Security Synchronization**: Menyelaraskan password di `.env`, `wazuh_dashboard.yml`, dan meng-generate bcrypt hashes baru di `internal_users.yml` agar autentikasi Dashboard & API berjalan lancar.
4.  **Agent Automation**: Mengonfigurasi `Dockerfile.dvwa` agar Wazuh Agent otomatis terdaftar (enroll) ke manager saat container dinyalakan.
5.  **Group Management**: Membuat grup `web-servers` pada Wazuh Manager secara otomatis untuk manajemen agent yang lebih rapi.

---

## PANDUAN UNTUK TEAMMATE (Langkah Selanjutnya)
Project ini sudah siap di sisi infrastruktur inti. Kamu (teammate) dapat melanjutkan bagian berikut:

1.  **Setup Ngrok**: Jalankan tunnel agar DVWA bisa diakses dari internet (lihat [Langkah 6](#6-aktifkan-ngrok-tunnel)).
2.  **API Connectivity Check**: Jika dashboard menunjukkan API offline, pastikan daemon `wazuh-analysisd` sudah running (`docker exec wazuh-manager /var/ossec/bin/wazuh-control status`).
3.  **Simulasi Serangan**: Lakukan serangan ke URL Ngrok dan pantau alert di Dashboard level 10-15.

---

## DAFTAR ISI
1. [Struktur Proyek](#1-struktur-proyek)
2. [Arsitektur Jaringan](#2-arsitektur-jaringan)
3. [Pre-Testing Checklist](#3-pre-testing-checklist)
4. [Panduan Eksekusi Tahap demi Tahap](#4-panduan-eksekusi-tahap-demi-tahap)
5. [Akses & Credentials](#5-akses--credentials)
6. [Inventori Internal](#6-inventori-internal)
7. [Panduan untuk Attacker](#7-panduan-untuk-attacker)
8. [Panduan untuk Analyst](#8-panduan-untuk-analyst)
9. [Troubleshooting](#9-troubleshooting)
10. [Skenario Demo](#10-skenario-demo)
11. [Catatan Khusus Windows](#11-catatan-khusus-windows)

---

---

## 1. STRUKTUR PROYEK

```
SOC-Project/
├── docker-compose.yml          ← Stack utama (Wazuh + DVWA)
├── Dockerfile.dvwa             ← Custom DVWA image + Wazuh Agent pre-installed
├── .env                        ← Credentials (JANGAN di-commit!)
├── .gitignore                  ← Exclude certs & .env dari Git
├── .gitattributes              ← Enforce LF line ending untuk .sh/.py (Windows fix)
│
├── config/
│   ├── certs.yml               ← Template sertifikat untuk generator
│   ├── ossec.conf              ← Konfigurasi Wazuh Manager
│   ├── ossec-agent.conf        ← Konfigurasi Wazuh Agent (untuk DVWA)
│   ├── wazuh_indexer.yml       ← Konfigurasi Opensearch
│   ├── wazuh_dashboard.yml     ← Konfigurasi koneksi Dashboard ke API
│   ├── internal_users.yml      ← User Wazuh Indexer (⚠️ hash perlu digenerate)
│   ├── apache-logging.conf     ← Konfigurasi log Apache DVWA
│   └── certs/                  ← Sertifikat SSL (di-generate otomatis)
│       ├── root-ca.pem
│       ├── wazuh-indexer.pem / wazuh-indexer-key.pem
│       ├── wazuh-manager.pem / wazuh-manager-key.pem
│       └── wazuh-dashboard.pem / wazuh-dashboard-key.pem
│
├── custom-rules/
│   ├── local_rules.xml         ← Custom detection rules (SQLi, XSS, dll)
│   └── custom_decoders.xml     ← Custom log decoders untuk DVWA
│
├── integrations/
│   └── custom-otx.py           ← Script Threat Intel OTX
│
├── scripts/
│   ├── deploy.ps1              ← Script deploy utama (Windows PowerShell)
│   ├── health-check.sh         ← Script health check (Linux/WSL/Git Bash)
│   ├── dvwa-entrypoint.sh      ← Entrypoint wrapper (internal, jangan diubah)
│   └── generate-hashes.sh      ← Script generate password hash
│
└── wazuh-logs/                 ← Persistensi log (auto-created)
```

---

## 2. ARSITEKTUR JARINGAN

```
INTERNET
    │
    │  (Attacker mengakses lewat sini)
    ▼
┌─────────────────────────────────┐
│  NGROK TUNNEL                   │
│  https://xxxx.ngrok-free.app    │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│  LAPTOP HOST (port 8080)        │
└────────────┬────────────────────┘
             │
             │  Docker Port Mapping (8080 → 80)
             ▼
═══════════════════════════════════════════════════════════
 DOCKER NETWORK: soc-net (172.20.0.0/24, bridge)
═══════════════════════════════════════════════════════════

 ┌─────────────────┐    ┌─────────────────┐
 │ DVWA Target     │    │ Wazuh Manager   │
 │ 172.20.0.20:80  │───▶│ 172.20.0.11     │
 │ (Wazuh Agent    │    │ :1514 (agent)   │
 │  PRE-INSTALLED) │    │ :1515 (enroll)  │
 └─────────────────┘    │ :55000 (API)    │
                         └────────┬────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
           ┌──────────────┐  ┌──────────────────────┐
           │ Wazuh Indexer│  │ Wazuh Dashboard      │
           │ 172.20.0.10  │  │ 172.20.0.12          │
           │ :9200        │  │ :5601 → localhost:443 │
           └──────────────┘  └──────────────────────┘
```

**Perbedaan dari versi lama:**
- DVWA sekarang menggunakan **custom Dockerfile** (`Dockerfile.dvwa`) yang sudah include Wazuh Agent
- Agent otomatis enrollment ke Manager saat container start
- Tidak perlu install agent manual lagi!

---

## 3. PRE-TESTING CHECKLIST

> ⚠️ **Jalankan checklist ini SEBELUM memulai testing/demo!**

### A. Prerequisites & Environment

- [ ] Docker Desktop terinstall dan **running**
- [ ] WSL2 backend aktif di Docker Desktop
- [ ] `vm.max_map_count=262144` sudah diset (lihat Section 11)
- [ ] RAM WSL minimal 8GB (`%USERPROFILE%\.wslconfig`)
- [ ] File `.env` ada dan semua password terisi
- [ ] Folder `config/certs/` berisi sertifikat SSL (min: `root-ca.pem`)
- [ ] Folder `wazuh-logs/` sudah dibuat

### B. Sertifikat & Keamanan

- [ ] Sertifikat SSL sudah di-generate (`docker compose --profile setup up wazuh-certs-generator`)
- [ ] File sertifikat lengkap: `root-ca.pem`, `wazuh-indexer.pem`, `wazuh-manager.pem`, `wazuh-dashboard.pem` + key masing-masing
- [ ] Password di `config/wazuh_dashboard.yml` **sinkron** dengan `API_PASSWORD` di `.env`
- [ ] (Opsional) Hash di `config/internal_users.yml` sudah di-generate ulang

### C. Container & Services

- [ ] `docker compose config` tidak ada error syntax
- [ ] `docker compose up -d` berhasil start semua 4 container
- [ ] `wazuh-indexer` → status **healthy** (tunggu ~2 menit)
- [ ] `wazuh-manager` → status **healthy** (tunggu ~3 menit setelah indexer)
- [ ] `wazuh-dashboard` → status **healthy** (tunggu ~2 menit setelah manager)
- [ ] `dvwa-target` → status **healthy**

### D. Konektivitas & Akses

- [ ] Dashboard bisa diakses: `https://localhost` (accept SSL warning)
- [ ] DVWA bisa diakses: `http://localhost:8080`
- [ ] Login Dashboard berhasil: `admin` / `WazuhSOC@2024!`
- [ ] Login DVWA berhasil: `admin` / `password`
- [ ] DVWA Security Level diset ke **LOW** (di DVWA Security menu)

### E. Agent & Monitoring

- [ ] Agent `dvwa-target` muncul di Dashboard → Menu **Agents**
- [ ] Status agent = **Active** (bukan Disconnected/Pending)
- [ ] Verifikasi via CLI: `docker exec wazuh-manager /var/ossec/bin/agent_control -lc`
- [ ] Log Apache mengalir: akses DVWA di browser lalu cek alert di Dashboard

### F. Detection Rules

- [ ] Coba SQLi payload → alert muncul di Dashboard (rule 100001/100002)
- [ ] Coba XSS payload → alert muncul (rule 100011)
- [ ] Custom rules terload: cek di Dashboard → Management → Rules → filter "100"

### G. Ngrok (Untuk Demo Remote)

- [ ] Ngrok authtoken sudah dikonfigurasi
- [ ] `ngrok http 8080` berhasil dan URL publik muncul
- [ ] URL Ngrok bisa diakses dari browser lain/HP
- [ ] URL sudah dicatat dan diberikan ke tim Attacker

### H. Threat Intelligence (Opsional)

- [ ] OTX API Key sudah diisi di `.env` dan `config/ossec.conf`
- [ ] Restart manager setelah isi API key: `docker restart wazuh-manager`

---

## 4. PANDUAN EKSEKUSI TAHAP DEMI TAHAP

### LANGKAH 0: Persiapan Awal (WAJIB, lakukan sekali)

**Untuk Windows (PowerShell sebagai Administrator):**
```powershell
# 1. Pastikan Docker Desktop sudah terinstall dan berjalan
# Download dari: https://www.docker.com/products/docker-desktop

# 2. Pastikan WSL2 backend aktif di Docker Desktop
# Settings → General → "Use the WSL2 based engine" ✓

# 3. Set vm.max_map_count via WSL (WAJIB untuk Wazuh Indexer)
wsl -d docker-desktop -u root -- sysctl -w vm.max_map_count=262144

# 4. Buat direktori yang dibutuhkan
mkdir -Force wazuh-logs, config\certs

# 5. Edit file environment sesuai kebutuhan
notepad .env
```

**Untuk Linux/Mac:**
```bash
# 1. Set kernel parameter untuk Wazuh Indexer (Opensearch)
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# 2. Buat direktori yang dibutuhkan
mkdir -p wazuh-logs config/certs

# 3. Beri permission eksekusi pada script
chmod +x scripts/health-check.sh
chmod +x scripts/generate-hashes.sh
chmod +x scripts/dvwa-entrypoint.sh
chmod +x integrations/custom-otx.py

# 4. Salin dan edit file environment
cp .env.example .env
nano .env
```

---

### LANGKAH 1: Generate Password Hashes (OPSIONAL tapi DISARANKAN)

Hash di `config/internal_users.yml` masih placeholder. Untuk keamanan:

```bash
# Via WSL / Git Bash:
./scripts/generate-hashes.sh

# Atau manual per-user:
docker run --rm wazuh/wazuh-indexer:4.7.3 bash -c \
  "plugins/opensearch-security/tools/hash.sh -p 'WazuhSOC@2024!'"
```

> ⚠️ Jika skip langkah ini, gunakan default hash yang sudah ada (untuk demo cukup).

---

### LANGKAH 2: Generate SSL Certificates

```bash
# Jalankan certificate generator (hanya sekali, lalu container exit otomatis)
docker compose --profile setup up wazuh-certs-generator

# Verifikasi sertifikat berhasil dibuat
# Windows:
dir config\certs\
# Linux:
ls -la config/certs/

# Output yang diharapkan:
# root-ca.pem, root-ca-key.pem
# wazuh-indexer.pem, wazuh-indexer-key.pem
# wazuh-manager.pem, wazuh-manager-key.pem
# wazuh-dashboard.pem, wazuh-dashboard-key.pem
```

> ⚠️ Jika folder `config/certs/` sudah ada sertifikat dari Wazuh official, skip langkah ini.

---

### LANGKAH 3: Deploy Stack Wazuh + DVWA

**Opsi A: Menggunakan Script (DISARANKAN untuk Windows)**
```powershell
# Full deploy (prerequisites + certs + start + health check)
.\scripts\deploy.ps1

# Atau langkah per langkah:
.\scripts\deploy.ps1 -Step certs     # Generate sertifikat
.\scripts\deploy.ps1 -Step start     # Start stack
.\scripts\deploy.ps1 -Step status    # Cek status
```

**Opsi B: Manual**
```bash
# Pull semua image dulu (lakukan saat ada internet)
docker compose pull

# Build custom DVWA image (dengan Wazuh Agent di dalamnya)
docker compose build dvwa

# Jalankan stack
docker compose up -d

# Monitor proses startup (akan memakan waktu 3-7 menit pertama kali)
docker compose logs -f

# Atau monitor container per container:
docker logs -f wazuh-indexer   # Tunggu "Node started"
docker logs -f wazuh-manager   # Tunggu "wazuh-manager started"
docker logs -f wazuh-dashboard # Tunggu "Server running"
docker logs -f dvwa-target     # Tunggu "Wazuh Agent is running"
```

**Estimasi waktu startup:** 3-7 menit (tergantung spesifikasi laptop)

> 💡 Pertama kali build `dvwa` akan memakan ~5 menit extra untuk download + install Wazuh Agent.

---

### LANGKAH 4: Health Check

**Windows:**
```powershell
.\scripts\deploy.ps1 -Step status
.\scripts\deploy.ps1 -Step agent
```

**Linux/WSL:**
```bash
./scripts/health-check.sh

# Jika ada masalah, coba auto-fix
./scripts/health-check.sh --fix
```

**Verifikasi manual Dashboard:**
```bash
# Windows PowerShell:
Invoke-WebRequest -Uri "https://localhost" -SkipCertificateCheck | Select-Object StatusCode

# Linux/WSL:
curl -sk https://localhost -o /dev/null -w "%{http_code}"
# Output yang diharapkan: 200 atau 302
```

Dashboard bisa dibuka di: `https://localhost`  
> ⚠️ Browser akan warning SSL (self-signed cert) — klik "Advanced" → "Accept Risk"

---

### LANGKAH 5: Verifikasi Agent (OTOMATIS!)

Berbeda dengan versi sebelumnya, **agent sekarang sudah otomatis terinstall dan enroll** berkat `Dockerfile.dvwa`. Kamu hanya perlu verifikasi:

```bash
# Cek dari Manager container
docker exec wazuh-manager /var/ossec/bin/agent_control -lc

# Output yang diharapkan:
# ID: 001, Name: dvwa-target, IP: 172.20.0.20, Status: Active
```

> 💡 Jika agent status "Disconnected", tunggu 1-2 menit karena enrollment butuh waktu.
> Jika masih fail, lihat bagian [Troubleshooting](#8-troubleshooting).

**Jika perlu install manual (fallback):**
```bash
docker exec -it dvwa-target bash
/var/ossec/bin/agent-auth -m 172.20.0.11 -A dvwa-target -G web-servers
/var/ossec/bin/wazuh-control restart
```

---

### LANGKAH 6: Aktifkan Ngrok Tunnel

```bash
# Pastikan DVWA aksesibel dulu
curl -I http://localhost:8080
# HTTP/1.1 200 OK

# Jalankan Ngrok (pastikan sudah setup authtoken)
ngrok http 8080

# Atau pakai named tunnel (jika sudah setup config ngrok):
ngrok start dvwa

# Catat URL yang diberikan Ngrok, contoh:
# https://a1b2c3d4.ngrok-free.app
# ⚡ Berikan URL ini kepada tim Attacker!
```

**Monitor traffic Ngrok:** http://localhost:4040

> ⚠️ **Ngrok free tier**: URL berubah setiap restart. Catat ulang setiap kali.

---

## 5. AKSES & CREDENTIALS

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| **Wazuh Dashboard** | https://localhost | `admin` | `WazuhSOC@2024!` |
| **Wazuh API** | http://localhost:55000 | `wazuh-wui` | `WazuhAPI@2024!` |
| **DVWA** | http://localhost:8080 | `admin` | `password` |
| **Ngrok Inspector** | http://localhost:4040 | - | - |

> 🔑 Semua password ada di file `.env`. Ganti sebelum demo jika perlu.  
> ⚠️ Password Dashboard dan API **harus cocok** dengan hash di `internal_users.yml` dan `wazuh_dashboard.yml`.

---

## 6. INVENTORI INTERNAL

| Komponen | IP Internal | Port | Fungsi |
|----------|-------------|------|--------|
| Wazuh Indexer | 172.20.0.10 | 9200 | Storage (Opensearch) |
| Wazuh Manager | 172.20.0.11 | 1514, 1515, 55000 | Analisis & Korelasi |
| Wazuh Dashboard | 172.20.0.12 | 5601 | Visualisasi |
| **DVWA Target** | **172.20.0.20** | **80** | **Honey-Target + Agent** |

**Network:** `soc-net` (172.20.0.0/24, bridge driver, IP statis)

---

## 7. PANDUAN UNTUK ATTACKER

> **Berikan informasi ini kepada tim Attacker saat demo:**

```
TARGET URL   : https://XXXX.ngrok-free.app   (isi URL Ngrok aktual)
LOGIN DVWA   : admin / password
DVWA SECURITY: Set ke LOW untuk demo (di DVWA Settings)

Jenis serangan yang akan terdeteksi SOC:
✓ SQL Injection (manual maupun sqlmap)
✓ XSS (Reflected & Stored)
✓ Brute Force login
✓ File Upload (web shell)
✓ Path Traversal / LFI / RFI
✓ Directory scanning (nikto, dirb, gobuster)
✓ Vulnerability scanner (nmap, nessus, acunetix)
```

**Contoh payload SQLi untuk demo:**
```
http://NGROK_URL/vulnerabilities/sqli/?id=1' OR '1'='1&Submit=Submit
http://NGROK_URL/vulnerabilities/sqli/?id=1 UNION SELECT 1,2--
```

**Contoh payload XSS untuk demo:**
```
http://NGROK_URL/vulnerabilities/xss_r/?name=<script>alert('XSS')</script>
```

---

## 8. PANDUAN UNTUK ANALYST

### Aktivasi Threat Intelligence (OTX)

1. Daftar di https://otx.alienvault.com
2. Dapatkan API Key dari profile
3. Edit file `.env`:
   ```
   OTX_API_KEY=your_actual_api_key_here
   ```
4. Edit `config/ossec.conf`, ganti di bagian `<integration>`:
   ```xml
   <api_key>your_actual_api_key_here</api_key>
   ```
5. Restart Wazuh Manager:
   ```bash
   docker restart wazuh-manager
   ```

### Melihat Alert di Dashboard

1. Buka https://localhost
2. Login dengan admin
3. Menu: **Threat Intelligence** → **Events** → Filter by rule group `soc-project`
4. Untuk FIM: **File Integrity Monitoring** → pilih agent `dvwa-target`

### Query Alert via API

```bash
# Cek agent status
curl -sk -u wazuh-wui:WazuhAPI@2024! http://localhost:55000/agents?pretty=true

# Ambil alert terbaru
curl -sk -u wazuh-wui:WazuhAPI@2024! http://localhost:55000/alerts?pretty=true&limit=10
```

---

## 9. TROUBLESHOOTING

### ❌ Masalah: Wazuh Indexer gagal start / container langsung exit

**Penyebab:** `vm.max_map_count` terlalu kecil  
**Solusi:**
```bash
# Windows (PowerShell Admin):
wsl -d docker-desktop -u root -- sysctl -w vm.max_map_count=262144

# Linux:
sudo sysctl -w vm.max_map_count=262144

# Lalu restart:
docker compose restart wazuh-indexer
```

---

### ❌ Masalah: Agent status "Disconnected" di Dashboard

**Penyebab:** Agent tidak bisa reach Manager  
**Solusi:**
```bash
# 1. Cek apakah agent berjalan di dalam DVWA
docker exec dvwa-target /var/ossec/bin/wazuh-control status

# 2. Jika tidak running, start manual
docker exec dvwa-target /var/ossec/bin/wazuh-control start

# 3. Re-enrollment jika perlu
docker exec dvwa-target /var/ossec/bin/agent-auth -m 172.20.0.11

# 4. Restart agent
docker exec dvwa-target /var/ossec/bin/wazuh-control restart

# 5. Cek log agent untuk error
docker exec dvwa-target tail -50 /var/ossec/logs/ossec.log

# 6. Verifikasi dari Manager
docker exec wazuh-manager /var/ossec/bin/agent_control -lc
```

---

### ❌ Masalah: Dashboard tidak bisa dibuka (ERR_CONNECTION_REFUSED)

**Penyebab:** Container Dashboard belum ready  
**Solusi:**
```bash
# Cek status
docker ps | grep dashboard

# Cek log
docker logs wazuh-dashboard --tail 50

# Biasanya butuh 2-3 menit setelah Manager healthy
# Tunggu dan coba lagi
```

---

### ❌ Masalah: DVWA tidak generate log di /var/log/apache2/

**Penyebab:** Apache logging tidak aktif  
**Solusi:**
```bash
docker exec dvwa-target bash -c "
  # Verifikasi Apache berjalan
  service apache2 status
  
  # Aktifkan logging
  a2enmod log_config
  service apache2 restart
  
  # Test generate log
  curl http://localhost/
  tail -5 /var/log/apache2/access.log
"
```

---

### ❌ Masalah: Alert tidak muncul di Dashboard saat SQLi

**Penyebab:** Rule mungkin tidak ter-load  
**Solusi:**
```bash
# Verifikasi rule dimuat
docker exec wazuh-manager /var/ossec/bin/wazuh-logtest

# Test rule secara manual
docker exec wazuh-manager bash -c "
  echo '192.168.1.1 - - [01/Jan/2024:00:00:00 +0700] \"GET /vulnerabilities/sqli/?id=1+UNION+SELECT+1,2-- HTTP/1.1\" 200 1234' | \
  /var/ossec/bin/wazuh-logtest
"
```

---

### ❌ Masalah: Ngrok URL berubah saat restart

**Penyebab:** Ngrok free tier tidak menjamin URL tetap  
**Solusi:**
```bash
# Ngrok sudah dikonfigurasi saat instalasi.
# Jalankan ulang saja:
ngrok http 8080

# URL baru akan digenerate, catat dan berikan ke Attacker
```

---

### ❌ Masalah: docker compose build dvwa GAGAL

**Penyebab:** Network issue saat download Wazuh Agent  
**Solusi:**
```bash
# Pastikan internet stabil, lalu rebuild
docker compose build --no-cache dvwa

# Jika masih gagal, fallback ke install manual:
# 1. Edit docker-compose.yml, ganti build section DVWA ke:
#    image: vulnerables/web-dvwa:latest
# 2. docker compose up -d
# 3. Install agent manual sesuai langkah di health-check.sh --agent
```

---

### Script Otomatis untuk semua cek

```bash
# Windows PowerShell:
.\scripts\deploy.ps1 -Step status    # Cek status
.\scripts\deploy.ps1 -Step agent     # Cek agent
.\scripts\deploy.ps1 -Step logs      # Lihat log live
.\scripts\deploy.ps1 -Step restart   # Restart semua

# Linux / WSL / Git Bash:
./scripts/health-check.sh          # Full check
./scripts/health-check.sh --fix    # Auto-fix masalah umum
./scripts/health-check.sh --agent  # Install/reinstall agent
```

---

## 10. SKENARIO DEMO

### Urutan Demo di Depan Dosen

**Durasi estimasi: 15-20 menit**

#### Fase 1: Show Dashboard Inventory (2 menit)
1. Buka https://localhost
2. Navigasi ke **Agents** — tunjukkan `dvwa-target` status **Active**
3. Klik agent → tunjukkan info: IP, OS, last keepalive

#### Fase 2: Show Log Flow (3 menit)
1. Minta Attacker buka Ngrok URL di browser
2. Di Dashboard, buka **Events** — tunjukkan log Apache masuk real-time
3. Filter by `agent.name: dvwa-target`

#### Fase 3: SQL Injection Detection (5 menit)
1. Attacker jalankan payload SQLi sederhana:
   ```
   https://NGROK_URL/vulnerabilities/sqli/?id=1' OR '1'='1
   ```
2. Di Dashboard → **Security Events** — muncul **alert merah level 12**
3. Klik alert → tunjukkan detail: rule ID 100001, MITRE T1190, source IP
4. Jika Attacker pakai sqlmap → alert level 12 + rule 100053 muncul

#### Fase 4: XSS Detection (3 menit)
1. Attacker inject XSS payload:
   ```
   https://NGROK_URL/vulnerabilities/xss_r/?name=<script>alert(1)</script>
   ```
2. Alert muncul → rule 100011, MITRE T1059.007
3. Tunjukkan detail: URL yang mengandung script tag

#### Fase 5: File Upload / Defacement (3 menit)
1. Attacker upload file PHP ke DVWA (DVWA → File Upload)
2. Alert FIM muncul → rule 100033 (New file in web dir) atau 100034 (PHP file dropped)
3. Tunjukkan detail file: nama, path, checksum

#### Fase 6: Threat Intelligence (2 menit)
1. Tunjukkan panel OTX integration aktif (jika API key sudah diisi)
2. Atau tunjukkan konfigurasi di ossec.conf sebagai bukti readiness
3. Jelaskan flow: alert → script custom-otx.py → query OTX → enrichment

#### Fase 7: Closing (2 menit)
1. Tunjukkan `wazuh-logs/` folder di laptop — bukti persistensi data
2. Tunjukkan custom rules di `custom-rules/local_rules.xml` — bukti kustomisasi
3. Tunjukkan custom decoders di `custom-rules/custom_decoders.xml` — nilai plus
4. Tunjukkan resource container (`docker stats`) — semua dalam batas normal

---

## 11. CATATAN KHUSUS WINDOWS

### Perbedaan Windows vs Linux

| Aspek | Windows | Linux |
|-------|---------|-------|
| Timezone | Hanya via env `TZ=Asia/Jakarta` | Bisa mount `/etc/localtime` |
| vm.max_map_count | `wsl -d docker-desktop -u root -- sysctl -w vm.max_map_count=262144` | `sudo sysctl -w vm.max_map_count=262144` |
| Script deploy | `.\scripts\deploy.ps1` (PowerShell) | `./scripts/health-check.sh` (Bash) |
| Path separator | Backslash `\` | Forward slash `/` |
| Docker | Docker Desktop + WSL2 | Docker Engine native |
| File permission | Otomatis (NTFS) | Butuh `chmod +x` |

### Tips Performa Windows

1. **Pastikan WSL2 backend aktif** di Docker Desktop (bukan Hyper-V legacy)
2. **Alokasi RAM WSL**: Edit `%USERPROFILE%\.wslconfig`:
   ```ini
   [wsl2]
   memory=8GB
   processors=4
   ```
3. **Restart WSL** setelah edit: `wsl --shutdown` lalu buka Docker Desktop lagi
4. **Matikan Windows Defender real-time** saat build Docker (opsional, untuk kecepatan)

### vm.max_map_count Persist di Windows

Setting `vm.max_map_count` akan **hilang** saat restart WSL. Untuk persist:

```powershell
# Buat file .wslconfig di %USERPROFILE%
@"
[wsl2]
memory=8GB
kernelCommandLine = sysctl.vm.max_map_count=262144
"@ | Out-File -Encoding utf8 "$env:USERPROFILE\.wslconfig"

# Restart WSL
wsl --shutdown
# Buka Docker Desktop lagi
```

---

## QUICK REFERENCE COMMANDS

```bash
# ============ WINDOWS POWERSHELL ============
.\scripts\deploy.ps1                  # Full deploy
.\scripts\deploy.ps1 -Step status     # Cek status
.\scripts\deploy.ps1 -Step agent      # Cek agent
.\scripts\deploy.ps1 -Step ngrok      # Start ngrok
.\scripts\deploy.ps1 -Step stop       # Stop semua
.\scripts\deploy.ps1 -Step logs       # Live logs
.\scripts\deploy.ps1 -Step restart    # Restart semua

# ============ UNIVERSAL (PowerShell / Bash / CMD) ============
# Start semua
docker compose up -d

# Stop semua
docker compose down

# Build ulang DVWA (setelah edit Dockerfile/config)
docker compose build dvwa

# Restart satu service
docker restart wazuh-manager

# Lihat log real-time
docker compose logs -f

# Masuk ke container
docker exec -it dvwa-target bash
docker exec -it wazuh-manager bash

# Cek alert real-time
docker exec wazuh-manager tail -f /var/ossec/logs/alerts/alerts.log

# Cek status agent
docker exec wazuh-manager /var/ossec/bin/agent_control -lc

# Resource usage
docker stats

# Validate compose file
docker compose config
```

---

*Dokumen ini disiapkan oleh: Infrastructure Builder*  
*Last updated: 2026-04-23 (v2 — health check & checklist update) | SOC Mini Project — Simulasi Serangan Real-time*
