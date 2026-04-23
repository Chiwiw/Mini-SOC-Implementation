#!/bin/bash
# ============================================================
# dvwa-entrypoint.sh - Wrapper untuk menjalankan DVWA + Wazuh Agent
# SOC Project | Infrastructure Builder
#
# Script ini menjalankan:
# 1. Wazuh Agent (background)
# 2. Apache + MySQL (foreground, default DVWA entrypoint)
# ============================================================

set -e

echo "============================================================"
echo "  DVWA + Wazuh Agent Container Starting..."
echo "  Wazuh Manager: ${WAZUH_MANAGER:-172.20.0.11}"
echo "  Agent Name:    ${WAZUH_AGENT_NAME:-dvwa-target}"
echo "============================================================"

# ============================================================
# STEP 1: Pastikan direktori log ada
# ============================================================
mkdir -p /var/log/apache2
mkdir -p /var/ossec/logs/integrations
touch /var/log/apache2/access.log
touch /var/log/apache2/error.log
touch /var/log/auth.log

# ============================================================
# STEP 2: Set ownership yang benar untuk Wazuh
# ============================================================
if [ -d "/var/ossec" ]; then
    chown -R root:wazuh /var/ossec/etc/ 2>/dev/null || true
fi

# ============================================================
# STEP 3: Agent auto-enrollment ke Manager
# ============================================================
start_wazuh_agent() {
    echo "[AGENT] Menunggu Wazuh Manager tersedia di ${WAZUH_MANAGER}..."

    # Tunggu manager siap (max 120 detik)
    local retries=0
    local max_retries=24
    while [ $retries -lt $max_retries ]; do
        if /var/ossec/bin/agent-auth -m "${WAZUH_MANAGER}" -A "${WAZUH_AGENT_NAME}" -G "${WAZUH_AGENT_GROUP}" 2>/dev/null; then
            echo "[AGENT] ✓ Enrollment berhasil ke Manager ${WAZUH_MANAGER}"
            break
        fi
        retries=$((retries + 1))
        echo "[AGENT] Retry enrollment ($retries/$max_retries)... Manager belum siap."
        sleep 5
    done

    if [ $retries -ge $max_retries ]; then
        echo "[AGENT] ⚠ Enrollment timeout! Agent mungkin sudah terdaftar atau Manager belum siap."
        echo "[AGENT] Agent akan tetap mencoba konek..."
    fi

    # Start Wazuh Agent
    echo "[AGENT] Starting Wazuh Agent..."
    /var/ossec/bin/wazuh-control start 2>/dev/null || true

    # Verifikasi agent berjalan
    sleep 3
    if /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q "is running"; then
        echo "[AGENT] ✓ Wazuh Agent is running!"
    else
        echo "[AGENT] ⚠ Wazuh Agent mungkin belum berjalan. Cek manual dengan:"
        echo "        docker exec dvwa-target /var/ossec/bin/wazuh-control status"
    fi
}

# Jalankan enrollment & start agent di background
start_wazuh_agent &

# ============================================================
# STEP 4: Jalankan DVWA (Apache + MySQL) — foreground
# ============================================================
echo "[DVWA] Starting Apache + MySQL (DVWA)..."

# Pastikan permission mysql benar (seperti bawaan image DVWA)
chown -R mysql:mysql /var/lib/mysql /var/run/mysqld 2>/dev/null || true

# Start MySQL
service mysql start || echo "[DVWA] ⚠ Gagal start MySQL"

# Tunggu service siap
sleep 3

# Jalankan Apache
echo "[DVWA] Menjalankan apache2..."
service apache2 start || echo "[DVWA] ⚠ Gagal start Apache"

# Jaga container tetap hidup
echo "[DVWA] Container berjalan. Menampilkan log apache..."
tail -f /var/log/apache2/error.log /var/log/apache2/access.log
