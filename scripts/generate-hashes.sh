#!/bin/bash
# ============================================================
# generate-hashes.sh - Generate bcrypt hashes untuk internal_users.yml
# SOC Project | Infrastructure Builder
#
# CARA PAKAI:
#   chmod +x scripts/generate-hashes.sh
#   ./scripts/generate-hashes.sh
#
# CATATAN:
#   Script ini menggunakan Docker untuk generate hash.
#   Pastikan Docker sudah berjalan.
#
# Setelah generate:
#   1. Copy hash yang ditampilkan
#   2. Paste ke config/internal_users.yml di field "hash:"
#   3. Restart stack: docker compose restart wazuh-indexer
# ============================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${CYAN}"
echo "============================================================"
echo "  Password Hash Generator untuk Wazuh Indexer"
echo "============================================================"
echo -e "${NC}"

# Baca password dari .env jika ada
if [ -f ".env" ]; then
    echo -e "${GREEN}[✓] File .env ditemukan, membaca password...${NC}"
    source .env 2>/dev/null || true
else
    echo -e "${YELLOW}[!] File .env tidak ditemukan.${NC}"
    echo -e "    Masukkan password secara manual."
fi

# Daftar user dan password
declare -A USERS
USERS["admin"]="${INDEXER_PASSWORD:-WazuhSOC@2024!}"
USERS["kibanaserver"]="${DASHBOARD_PASSWORD:-KibanaSOC@2024!}"
USERS["wazuh-wui"]="${API_PASSWORD:-WazuhAPI@2024!}"

echo ""
echo -e "${BOLD}Generating bcrypt hashes using Docker...${NC}"
echo -e "${YELLOW}(Pastikan Docker sudah berjalan!)${NC}"
echo ""

# Check Docker
if ! docker info &> /dev/null; then
    echo -e "${RED}[✗] Docker tidak berjalan! Start Docker Desktop dulu.${NC}"
    exit 1
fi

echo "============================================================"
echo "  HASIL HASH - Salin ke config/internal_users.yml"
echo "============================================================"
echo ""

for user in "${!USERS[@]}"; do
    password="${USERS[$user]}"
    echo -e "${CYAN}User: ${user}${NC}"
    echo -e "  Password: ${password}"
    echo -n "  Hash: "

    # Generate hash menggunakan Docker
    hash=$(docker run --rm wazuh/wazuh-indexer:4.7.3 bash -c \
        "plugins/opensearch-security/tools/hash.sh -p '${password}'" 2>/dev/null | tail -1)

    if [ -n "$hash" ]; then
        echo -e "${GREEN}${hash}${NC}"
    else
        echo -e "${RED}ERROR - Gagal generate hash${NC}"
        echo -e "  Coba manual: docker run --rm wazuh/wazuh-indexer:4.7.3 bash -c \"plugins/opensearch-security/tools/hash.sh -p '${password}'\""
    fi
    echo ""
done

echo "============================================================"
echo -e "${BOLD}INSTRUKSI:${NC}"
echo "1. Copy setiap hash di atas"
echo "2. Buka config/internal_users.yml"
echo "3. Ganti value 'hash:' untuk setiap user"
echo "4. Restart indexer: docker compose restart wazuh-indexer"
echo "============================================================"
