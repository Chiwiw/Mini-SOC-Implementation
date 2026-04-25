# Mini SOC Implementation

| Nama | NRP |
|------|-----|
| Hanif Mawla Faizi | 5027241064 |
| Muhammad Khosyi Syehab | 5027241089 |
| Yasykur Khalis Jati Maulana Yuwono | 5027241112 |

## Executive Summary
Mini SOC Implementation adalah proyek simulasi Security Operations Center (SOC) berbasis Wazuh yang dirancang untuk mendeteksi aktivitas serangan terhadap aplikasi web rentan (DVWA) secara near real-time. Proyek ini menyatukan proses koleksi log, korelasi event, deteksi berbasis rule, serta visualisasi alert dalam satu lingkungan yang dapat direplikasi menggunakan Docker.

Status saat ini: infrastruktur inti stabil, pipeline deteksi aktif, dan siap digunakan untuk kebutuhan demo teknis maupun pelaporan akademik.

## Deskripsi Proyek
Proyek ini membangun lingkungan SOC skala mini dengan pendekatan practical-lab: attacker traffic diarahkan ke DVWA, log diproses oleh Wazuh Agent dan Manager, lalu alert disimpan pada Indexer dan ditampilkan melalui Dashboard.

Lingkup kerja mencakup:
1. Provisioning stack SIEM menggunakan Docker Compose.
2. Integrasi endpoint target (DVWA) dengan Wazuh Agent.
3. Pengembangan custom decoder dan custom rules untuk use case web attack.
4. Validasi alur deteksi melalui simulasi SQL Injection, XSS, dan scanner activity.
5. Persiapan integrasi Threat Intelligence berbasis OTX.

## Objectives
1. Menyediakan arsitektur SOC mini yang mudah direplikasi lintas perangkat.
2. Menghasilkan alert yang dapat ditindaklanjuti dari aktivitas serangan web.
3. Menunjukkan alur kerja SOC end-to-end: ingestion, detection, analysis, reporting.
4. Meningkatkan kualitas operasional melalui otomatisasi deployment dan health-check.

## System Architecture
### Core Services
1. `wazuh-indexer`: penyimpanan event dan alert.
2. `wazuh-manager`: pemrosesan event, decoder, dan rule engine.
3. `wazuh-dashboard`: observabilitas dan investigasi alert.
4. `dvwa-target`: target aplikasi web dengan Wazuh Agent.

### Data Flow
1. Request menyerang DVWA dari lokal atau internet (melalui Ngrok).
2. Apache menghasilkan access log pada host target.
3. Wazuh Agent mengirim log ke Wazuh Manager.
4. Wazuh Manager melakukan decoding, enrichment, dan rule matching.
5. Alert diindeks ke Wazuh Indexer dan divisualisasikan di Wazuh Dashboard.

## Engineering Deliverables
1. Stabilisasi startup service kritikal pada manager dan target.
2. Refactor rule dan decoder agar kompatibel PCRE2 serta lebih tahan error parsing.
3. Sinkronisasi kredensial lintas `.env`, konfigurasi dashboard, dan user hash indexer.
4. Otomatisasi enrollment agent melalui image DVWA kustom dan entrypoint terkontrol.
5. Standardisasi grouping agent (`web-servers`) untuk pengelolaan endpoint.

## Apa yang Membuat Proyek Ini Lebih Baik
Dibanding banyak implementasi kelas yang berhenti pada tahap "container berhasil jalan", proyek ini dirancang dengan pendekatan SOC engineering yang lebih matang: dapat dideploy ulang, dapat diverifikasi, dapat dipulihkan, dan dapat dipresentasikan sebagai pipeline keamanan yang utuh.

1. **Reliability by design, bukan sekadar startup success**
Fokus kami bukan hanya membuat service `Up`, tetapi memastikan dependency chain Wazuh (Indexer -> Manager -> Dashboard -> Agent) tetap stabil saat cold start, restart, dan recovery ringan. Ini terlihat dari adanya prosedur health verification, pengecekan status agent, serta langkah korektif yang eksplisit pada runbook.

2. **Automated endpoint onboarding pada target serangan**
Berbeda dari pola umum yang mengandalkan instalasi manual agent setiap kali lab diulang, target DVWA kami sudah dibangun sebagai image kustom dengan Wazuh Agent pre-installed, auto-auth, dan auto-start. Hasilnya, waktu setup lebih singkat, proses onboarding lebih konsisten, dan risiko human error saat demo berkurang signifikan.

3. **Detection engineering yang kontekstual terhadap web attack**
Kami tidak hanya memakai rule bawaan. Proyek ini menyertakan custom decoder dan custom rules yang dituning untuk pola serangan aplikasi web yang benar-benar diuji pada skenario demo (SQLi payload, XSS payload, scanner user-agent). Pendekatan ini meningkatkan relevansi alert dan mengurangi noise yang tidak berguna untuk analisis.

4. **Konfigurasi keamanan lintas komponen yang tersinkronisasi**
Salah satu kegagalan paling umum di proyek sejenis adalah mismatch kredensial antara dashboard, API, dan indexer user store. Proyek ini menangani titik gagal tersebut dengan sinkronisasi konfigurasi `.env`, `wazuh_dashboard.yml`, dan `internal_users.yml`, sehingga autentikasi sistem lebih andal saat deployment ulang.

5. **Operational documentation yang bisa langsung dipakai tim**
Runbook disusun sebagai dokumen operasional, bukan catatan personal. Isinya mencakup quick start, full deployment, validasi pasca deploy, troubleshooting matrix, dan catatan operasional harian. Ini membuat knowledge transfer antar anggota kelompok berjalan lebih baik dan mengurangi ketergantungan pada satu orang operator.

6. **Demo-readiness untuk evaluasi akademik dan teknis**
Arsitektur, alur validasi, dan skenario uji dirancang agar mudah dibuktikan secara live: serangan dilakukan, log masuk, alert muncul, dan detail investigasi dapat ditunjukkan di dashboard. Dengan demikian proyek tidak hanya "terpasang", tetapi juga menunjukkan kemampuan deteksi yang dapat diverifikasi oleh dosen maupun reviewer teknis.

7. **Threat intelligence ready tanpa merombak arsitektur inti**
Integrasi OTX disiapkan sebagai jalur pengayaan IOC sehingga pipeline dapat berkembang ke intelligence-driven monitoring. Nilai tambahnya adalah skalabilitas: proyek tetap ringan untuk praktikum, tetapi punya jalur ekspansi realistis menuju SOC yang lebih production-minded.

### Key Differentiators at a Glance

| Area | Implementasi Umum | Implementasi Tim Kami | Dampak Praktis |
|------|-------------------|-----------------------|----------------|
| Deployment quality | Fokus pada `docker compose up` berhasil | Menjamin stabilitas dependency chain dan recovery flow | Risiko gagal demo menurun, startup lebih prediktif |
| Endpoint onboarding | Install/enroll agent manual berulang | DVWA custom image dengan agent pre-installed dan auto-enroll | Setup ulang lab lebih cepat dan konsisten |
| Detection logic | Mengandalkan rule bawaan | Custom decoder + custom rules untuk SQLi, XSS, scanner pattern | Alert lebih relevan, noise analisis berkurang |
| Security config | Konfigurasi credential parsial | Sinkronisasi `.env`, dashboard config, dan indexer users | Mengurangi failure autentikasi antar layanan |
| Team operability | Dokumentasi tipis atau personal notes | Runbook operasional formal: quick start, validasi, troubleshooting | Transfer knowledge tim lebih efektif |
| Demo readiness | Sulit menunjukkan alur end-to-end | Skenario serangan dan validasi alert disiapkan sebagai pipeline utuh | Reviewer dapat memverifikasi kemampuan deteksi secara langsung |
| Scalability path | Sulit ditingkatkan setelah demo | Fondasi OTX sudah disiapkan untuk enrichment IOC | Proyek tetap ringan sekarang, siap ditingkatkan ke SOC yang lebih advanced |

## Repository Structure
1. `docker-compose.yml`: orkestrasi service utama.
2. `Dockerfile.dvwa`: image DVWA kustom + Wazuh Agent.
3. `config/`: konfigurasi service, security user, sertifikat.
4. `custom-rules/`: custom decoders dan custom rules.
5. `integrations/`: script integrasi intelijen ancaman.
6. `scripts/`: utilitas deploy, health-check, hash generation.

## Validation Scenarios
1. SQL Injection request menghasilkan alert sesuai rule web attack.
2. XSS payload terdeteksi melalui rule custom.
3. User-agent scanner (simulasi sqlmap/nikto) teridentifikasi sebagai aktivitas anomali.

## Getting Started
Seluruh langkah operasional dipisahkan pada:

- [RUNBOOK.md](RUNBOOK.md)

Runbook mencakup quick start, deployment penuh, health verification, validasi agent, koneksi Ngrok, dan troubleshooting.

### Open Source Setup Notes
Untuk kolaborasi publik, file sensitif tidak lagi disimpan di repository.

1. Buat file environment lokal dari template:
	```bash
	cp .env.example .env
	```
	(Windows PowerShell)
	```powershell
	Copy-Item .env.example .env
	```
2. Isi semua placeholder di `.env` dengan credential milikmu.
3. Generate sertifikat lokal saat setup pertama:
	```bash
	docker compose --profile setup up wazuh-certs-generator
	```
4. Jangan commit `.env` dan isi `config/certs/` ke repository.

## Security Notes
1. Jangan commit `.env`, secret, atau material private key.
2. Ganti semua credential default sebelum demo publik.
3. Gunakan tunnel publik hanya selama pengujian.

## Team Roles
1. Infrastructure SOC Engineer: arsitektur, deployment, dan stabilisasi layanan.
2. Threat Intelligence/Security Analyst: tuning deteksi, analisis alert, enrichment IOC.
3. Red Teamer: eksekusi simulasi serangan untuk validasi deteksi.

## References
1. Wazuh Documentation: https://documentation.wazuh.com
2. DVWA Repository: https://github.com/digininja/DVWA
3. Ngrok Documentation: https://ngrok.com/docs
