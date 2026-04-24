# Mini SOC Operations Runbook

Dokumen ini adalah panduan operasional resmi untuk menyiapkan, menjalankan, memverifikasi, dan memulihkan stack Mini SOC.

## 1. Tujuan Dokumen
1. Menstandarkan proses deployment agar konsisten antar anggota tim.
2. Menyediakan prosedur validasi layanan dan deteksi pasca-deploy.
3. Menyediakan tindakan korektif cepat saat terjadi gangguan.

## 2. Prasyarat

### 2.1 Kebutuhan Sistem
1. Docker Engine atau Docker Desktop aktif.
2. File `.env` tersedia dan terisi.
3. Direktori `config/certs/` tersedia.
4. Kernel parameter `vm.max_map_count=262144` sudah diterapkan.

### 2.2 Konfigurasi `vm.max_map_count`
```bash
# Linux
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# Windows (PowerShell, Administrator)
wsl -d docker-desktop -u root -- sysctl -w vm.max_map_count=262144
```

## 3. Quick Start
Gunakan prosedur ini jika environment sudah siap.

```bash
docker compose pull
docker compose build dvwa
docker compose up -d
./scripts/health-check.sh
docker exec wazuh-manager /var/ossec/bin/agent_control -lc
```

## 4. Prosedur Deployment Lengkap

### 4.1 Persiapan Direktori dan Permission
```bash
mkdir -p wazuh-logs config/certs
chmod +x scripts/health-check.sh scripts/generate-hashes.sh scripts/dvwa-entrypoint.sh integrations/custom-otx.py
```

### 4.2 Generate Password Hash (Opsional, Direkomendasikan)
```bash
./scripts/generate-hashes.sh
```

Alternatif manual:
```bash
docker run --rm wazuh/wazuh-indexer:4.7.3 bash -c "plugins/opensearch-security/tools/hash.sh -p 'WazuhSOC@2024!'"
```

### 4.3 Generate Sertifikat
Jalankan satu kali saat inisialisasi proyek.

```bash
docker compose --profile setup up wazuh-certs-generator
ls -la config/certs/
```

### 4.4 Start Services
```bash
docker compose pull
docker compose build dvwa
docker compose up -d
```

### 4.5 Monitoring Startup
```bash
docker compose logs -f
```

## 5. Validasi Pasca Deployment

### 5.1 Validasi Service Health
```bash
./scripts/health-check.sh
```

Perbaikan otomatis masalah umum:
```bash
./scripts/health-check.sh --fix
```

### 5.2 Validasi Dashboard
```bash
curl -sk https://localhost -o /dev/null -w "%{http_code}\n"
```

Status yang diharapkan: `200` atau `302`.

### 5.3 Validasi Agent
```bash
docker exec wazuh-manager /var/ossec/bin/agent_control -lc
```

Status yang diharapkan: `dvwa-target` dalam kondisi `Active`.

Jika agent belum aktif:
```bash
docker exec dvwa-target /var/ossec/bin/agent-auth -m 172.20.0.11 -A dvwa-target -G web-servers
docker exec dvwa-target /var/ossec/bin/wazuh-control restart
```

## 6. Eksposur Publik untuk Simulasi

### 6.1 Verifikasi DVWA Lokal
```bash
curl -I http://localhost:8080
```

### 6.2 Jalankan Tunnel Ngrok
```bash
ngrok http 8080
```

Catat URL publik yang dihasilkan untuk kebutuhan uji serangan eksternal.

## 7. Endpoint dan Kredensial Default
1. Wazuh Dashboard: `https://localhost`
2. Wazuh API: `http://localhost:55000`
3. DVWA: `http://localhost:8080`

Kredensial default (sesuaikan dengan isi `.env`):
1. Dashboard: `admin` / `WazuhSOC@2024!`
2. API: `wazuh-wui` / `WazuhAPI@2024!`
3. DVWA: `admin` / `password`

## 8. Troubleshooting Matrix

### 8.1 Indexer gagal start
Kemungkinan penyebab: `vm.max_map_count` belum sesuai.

```bash
sudo sysctl -w vm.max_map_count=262144
docker compose restart wazuh-indexer
```

### 8.2 Agent berstatus Disconnected
Kemungkinan penyebab: komunikasi agent-manager terganggu atau enrollment belum selesai.

```bash
docker exec dvwa-target /var/ossec/bin/wazuh-control status
docker exec dvwa-target /var/ossec/bin/wazuh-control restart
docker exec wazuh-manager /var/ossec/bin/agent_control -lc
```

### 8.3 Dashboard tidak dapat diakses
Kemungkinan penyebab: service belum siap penuh atau dependensi belum healthy.

```bash
docker logs wazuh-dashboard --tail 50
docker ps
```

## 9. Perintah Operasional Harian
```bash
# Menjalankan stack
docker compose up -d

# Menghentikan stack
docker compose down

# Build ulang image DVWA
docker compose build dvwa

# Monitoring log realtime
docker compose logs -f

# Monitoring penggunaan resource
docker stats
```

## 10. Catatan Operasional
1. Hindari `docker compose down -v` bila ingin mempertahankan data/log untuk evaluasi.
2. Jalankan validasi health dan status agent setelah setiap restart stack.
3. Simpan hasil observasi alert sebagai bukti performa deteksi pada laporan.
