#!/bin/bash
# ============================================================
# health-check.sh - SOC Stack Health Check & Troubleshooting
# SOC Project | Infrastructure Builder
#
# Cara penggunaan:
#   chmod +x scripts/health-check.sh
#   ./scripts/health-check.sh            # Full health check
#   ./scripts/health-check.sh --fix      # Auto-fix masalah umum
#   ./scripts/health-check.sh --agent    # Install agent di DVWA
# ============================================================

set -euo pipefail

# ============================================================
# KONFIGURASI
# ============================================================
COMPOSE_FILE="docker-compose.yml"
WAZUH_MANAGER_IP="172.20.0.11"
WAZUH_DASHBOARD_URL="https://localhost"
WAZUH_API_URL="http://localhost:55000"
DVWA_URL="http://localhost:8080"
WAZUH_API_USER="wazuh-wui"
WAZUH_API_PASS="WazuhAPI@2024!"  # Harus sama dengan API_PASSWORD di .env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ============================================================
# HELPER FUNCTIONS
# ============================================================

print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}============================================================${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}============================================================${NC}"
}

print_ok()   { echo -e "  ${GREEN}[✓] $1${NC}"; }
print_fail() { echo -e "  ${RED}[✗] $1${NC}"; }
print_warn() { echo -e "  ${YELLOW}[!] $1${NC}"; }
print_info() { echo -e "  ${CYAN}[i] $1${NC}"; }

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_fail "Command '$1' tidak ditemukan. Install dulu!"
        return 1
    fi
    print_ok "Command '$1' tersedia"
}

# ============================================================
# CHECK 1: PREREQUISITES
# ============================================================
check_prerequisites() {
    print_header "CHECK 1: Prerequisites"
    check_command "docker"
    check_command "docker-compose" || check_command "docker compose"
    check_command "curl"
    check_command "ngrok" || print_warn "ngrok tidak ditemukan (opsional, download dari ngrok.com)"

    # Cek Docker daemon berjalan
    if docker info &> /dev/null; then
        print_ok "Docker daemon berjalan"
    else
        print_fail "Docker daemon tidak berjalan! Jalankan: sudo systemctl start docker"
    fi

    # Cek file compose ada
    if [ -f "$COMPOSE_FILE" ]; then
        print_ok "docker-compose.yml ditemukan"
    else
        print_fail "docker-compose.yml tidak ditemukan di direktori ini!"
    fi

    # Cek file .env
    if [ -f ".env" ]; then
        print_ok ".env file ditemukan"
        # Cek OTX key sudah diisi
        if grep -q "PASTE_YOUR_OTX_API_KEY_HERE" .env; then
            print_warn "OTX_API_KEY belum diisi di .env (opsional, untuk threat intel)"
        else
            print_ok "OTX_API_KEY sudah dikonfigurasi"
        fi
    else
        print_fail ".env file tidak ditemukan!"
        print_info "  Buat file .env dengan credentials. Lihat INFRAS_README.md."
    fi
}

# ============================================================
# CHECK 2: CONTAINER STATUS
# ============================================================
check_containers() {
    print_header "CHECK 2: Container Status"

    local containers=("wazuh-indexer" "wazuh-manager" "wazuh-dashboard" "dvwa-target")

    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            local status
            status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
            local state
            state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")

            if [ "$state" == "running" ]; then
                if [ "$status" == "healthy" ] || [ "$status" == "no-healthcheck" ]; then
                    print_ok "$container: Running ($status)"
                elif [ "$status" == "starting" ]; then
                    print_warn "$container: Running (health check masih starting...)"
                else
                    print_fail "$container: Running tapi health check UNHEALTHY"
                fi
            else
                print_fail "$container: State = $state"
            fi
        else
            print_fail "$container: TIDAK BERJALAN"
        fi
    done
}

# ============================================================
# CHECK 3: PORT & CONNECTIVITY
# ============================================================
check_connectivity() {
    print_header "CHECK 3: Port & Connectivity"

    local ports=(
        "1514:Agent Communication (TCP)"
        "1515:Agent Enrollment"
        "55000:Wazuh API"
        "8080:DVWA (HTTP)"
        "443:Wazuh Dashboard (HTTPS)"
    )

    for port_info in "${ports[@]}"; do
        local port="${port_info%%:*}"
        local desc="${port_info#*:}"

        if curl -sk --connect-timeout 3 "http://localhost:${port}" &> /dev/null ||
           curl -sk --connect-timeout 3 "https://localhost:${port}" &> /dev/null ||
           nc -z localhost "$port" 2>/dev/null; then
            print_ok "Port $port ($desc): OPEN"
        else
            print_fail "Port $port ($desc): CLOSED atau tidak responsif"
        fi
    done

    # Cek DVWA khusus
    echo ""
    print_info "Testing DVWA response..."
    local dvwa_code
    dvwa_code=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 "$DVWA_URL" 2>/dev/null || echo "000")
    if [ "$dvwa_code" == "200" ] || [ "$dvwa_code" == "302" ]; then
        print_ok "DVWA HTTP Response: $dvwa_code - Aksesibel!"
    else
        print_fail "DVWA HTTP Response: $dvwa_code - Tidak aksesibel!"
    fi
}

# ============================================================
# CHECK 4: WAZUH AGENT STATUS
# ============================================================
check_agents() {
    print_header "CHECK 4: Wazuh Agent Status"

    # Cek via API
    print_info "Querying Wazuh API untuk status agent..."

    local api_response
    if api_response=$(curl -sk -u "${WAZUH_API_USER}:${WAZUH_API_PASS}" \
        "${WAZUH_API_URL}/agents?pretty=true" 2>/dev/null); then

        local total_agents
        total_agents=$(echo "$api_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('total_affected_items',0))" 2>/dev/null || echo "0")

        if [ "$total_agents" -gt "0" ] 2>/dev/null; then
            print_ok "Agent terdaftar: $total_agents"
            echo "$api_response" | python3 -c "
import sys, json
d = json.load(sys.stdin)
agents = d.get('data', {}).get('affected_items', [])
for a in agents:
    status = a.get('status', 'unknown')
    name = a.get('name', 'unknown')
    ip = a.get('ip', 'unknown')
    symbol = '✓' if status == 'active' else '✗'
    print(f'  [{symbol}] {name} ({ip}) - Status: {status}')
" 2>/dev/null || echo "  (gagal parse response)"
        else
            print_fail "Tidak ada agent yang terdaftar!"
            print_info "Jalankan: ./scripts/health-check.sh --agent untuk install agent ke DVWA"
        fi
    else
        print_warn "Tidak bisa konek ke Wazuh API. Manager mungkin belum siap."
    fi

    # Cek langsung dari container
    echo ""
    print_info "Cek agent list dari Manager container..."
    if docker exec wazuh-manager /var/ossec/bin/agent_control -lc 2>/dev/null; then
        :
    else
        print_warn "Tidak bisa eksekusi agent_control di container"
    fi
}

# ============================================================
# CHECK 5: LOG FLOW
# ============================================================
check_log_flow() {
    print_header "CHECK 5: Log Flow (Last 5 Alerts)"

    print_info "Mengambil 5 alert terbaru dari Wazuh Manager..."

    if docker exec wazuh-manager tail -n 50 /var/ossec/logs/alerts/alerts.log 2>/dev/null | \
       grep -E "Rule:|srcip:|agent_name:" | tail -20; then
        print_ok "Log alerts mengalir dengan baik"
    else
        print_warn "Belum ada log alert atau manager belum generate alert"
        print_info "Coba akses DVWA di browser dan lakukan beberapa request"
    fi
}

# ============================================================
# CHECK 6: NGROK STATUS
# ============================================================
check_ngrok() {
    print_header "CHECK 6: Ngrok Tunnel Status"

    local ngrok_api="http://localhost:4040/api/tunnels"
    local ngrok_response

    if ngrok_response=$(curl -s --connect-timeout 3 "$ngrok_api" 2>/dev/null); then
        local public_url
        public_url=$(echo "$ngrok_response" | python3 -c "
import sys, json
d = json.load(sys.stdin)
tunnels = d.get('tunnels', [])
for t in tunnels:
    if 'public_url' in t:
        print(t['public_url'])
" 2>/dev/null || echo "")

        if [ -n "$public_url" ]; then
            print_ok "Ngrok tunnel AKTIF!"
            echo ""
            echo -e "  ${BOLD}${GREEN}>>> URL untuk Attacker: $public_url ${NC}"
            echo ""
        else
            print_fail "Ngrok berjalan tapi tidak ada tunnel aktif"
        fi
    else
        print_warn "Ngrok tidak berjalan atau belum dikonfigurasi"
        print_info "Jalankan: ngrok http 8080"
        print_info "Atau dengan config: ngrok start dvwa"
    fi
}

# ============================================================
# AUTO-FIX COMMON ISSUES
# ============================================================
auto_fix() {
    print_header "AUTO-FIX Mode"

    # Fix 1: vm.max_map_count untuk Elasticsearch/Opensearch
    print_info "Setting vm.max_map_count untuk Wazuh Indexer..."
    if sudo sysctl -w vm.max_map_count=262144 2>/dev/null; then
        print_ok "vm.max_map_count set ke 262144"
        # Persist
        echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
    else
        print_warn "Gagal set vm.max_map_count (perlu sudo)"
        print_info "Jalankan manual: sudo sysctl -w vm.max_map_count=262144"
    fi

    # Fix 2: Restart container yang unhealthy
    local containers=("wazuh-indexer" "wazuh-manager" "wazuh-dashboard" "dvwa-target")
    for container in "${containers[@]}"; do
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "")
        if [ "$status" == "unhealthy" ]; then
            print_warn "Restarting $container (unhealthy)..."
            docker restart "$container"
            print_ok "$container restarted"
        fi
    done

    # Fix 3: Buat direktori wazuh-logs jika belum ada
    if [ ! -d "./wazuh-logs" ]; then
        mkdir -p ./wazuh-logs
        print_ok "Direktori wazuh-logs dibuat"
    fi

    print_ok "Auto-fix selesai! Jalankan health check lagi untuk verifikasi."
}

# ============================================================
# INSTALL AGENT KE DVWA
# ============================================================
install_agent() {
    print_header "INSTALL WAZUH AGENT ke DVWA"

    print_info "Memulai instalasi Wazuh Agent di container dvwa-target..."
    echo ""

    # Cek container DVWA berjalan
    if ! docker ps --format "{{.Names}}" | grep -q "dvwa-target"; then
        print_fail "Container dvwa-target tidak berjalan!"
        exit 1
    fi

    # Jalankan instalasi di dalam container
    docker exec -it dvwa-target bash -c '
echo "=== Installing Wazuh Agent ==="

# Install dependencies
apt-get update -qq && apt-get install -y -qq curl gnupg2

# Add Wazuh repo
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add -
echo "deb https://packages.wazuh.com/4.x/apt/ stable main" | tee /etc/apt/sources.list.d/wazuh.list

# Install agent
apt-get update -qq && apt-get install -y -qq wazuh-agent

# Set manager address
WAZUH_MANAGER="172.20.0.11" WAZUH_AGENT_NAME="dvwa-target" WAZUH_AGENT_GROUP="web-servers" \
  /var/ossec/bin/wazuh-control start 2>/dev/null || true

echo "=== Agent installed, applying config ==="
'

    # Copy konfigurasi agent
    if [ -f "./config/ossec-agent.conf" ]; then
        docker cp "./config/ossec-agent.conf" "dvwa-target:/var/ossec/etc/ossec.conf"
        print_ok "Konfigurasi agent disalin"
    fi

    # Restart agent
    docker exec dvwa-target /var/ossec/bin/wazuh-control restart 2>/dev/null || true

    print_ok "Agent instalasi selesai!"
    print_info "Tunggu 30 detik lalu cek status di Wazuh Dashboard."
    print_info "Atau jalankan: ./scripts/health-check.sh dan cek bagian Agent Status"
}

# ============================================================
# TAMPILKAN INFO INVENTORI
# ============================================================
show_inventory() {
    print_header "SOC INVENTORY"

    echo ""
    echo -e "${BOLD}  Internal Network (soc-net: 172.20.0.0/24):${NC}"
    echo -e "  ┌─────────────────────────────────────────────────────┐"
    echo -e "  │  Wazuh Indexer    : 172.20.0.10 (port 9200)        │"
    echo -e "  │  Wazuh Manager    : 172.20.0.11 (port 1514, 1515)  │"
    echo -e "  │  Wazuh Dashboard  : 172.20.0.12 (port 5601)        │"
    echo -e "  │  DVWA Target      : 172.20.0.20 (port 80)          │"
    echo -e "  └─────────────────────────────────────────────────────┘"
    echo ""
    echo -e "${BOLD}  Akses Eksternal (dari laptop):${NC}"
    echo -e "  ┌─────────────────────────────────────────────────────┐"
    echo -e "  │  Dashboard SOC    : https://localhost               │"
    echo -e "  │  Wazuh API        : http://localhost:55000          │"
    echo -e "  │  DVWA (local)     : http://localhost:8080           │"
    echo -e "  │  Ngrok Inspector  : http://localhost:4040           │"
    echo -e "  └─────────────────────────────────────────────────────┘"
    echo ""
    echo -e "${BOLD}  Credentials (lihat file .env untuk password):${NC}"
    echo -e "  ┌─────────────────────────────────────────────────────┐"
    echo -e "  │  Dashboard User   : admin                           │"
    echo -e "  │  DVWA User        : admin / password                │"
    echo -e "  └─────────────────────────────────────────────────────┘"
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "  ███████╗ ██████╗  ██████╗    ██╗  ██╗███████╗ █████╗ ██╗  ████████╗██╗  ██╗"
    echo "  ██╔════╝██╔═══██╗██╔════╝    ██║  ██║██╔════╝██╔══██╗██║  ╚══██╔══╝██║  ██║"
    echo "  ███████╗██║   ██║██║         ███████║█████╗  ███████║██║     ██║   ███████║"
    echo "  ╚════██║██║   ██║██║         ██╔══██║██╔══╝  ██╔══██║██║     ██║   ██╔══██║"
    echo "  ███████║╚██████╔╝╚██████╗    ██║  ██║███████╗██║  ██║███████╗██║   ██║  ██║"
    echo "  ╚══════╝ ╚═════╝  ╚═════╝    ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "  ${CYAN}Mini SOC Health Check | Infrastructure Builder${NC}"
    echo -e "  $(date)"

    # Parse arguments
    case "${1:-}" in
        "--fix")
            auto_fix
            ;;
        "--agent")
            install_agent
            ;;
        "--inventory"|"-i")
            show_inventory
            ;;
        "--agents"|"-a")
            check_agents
            ;;
        "--ngrok"|"-n")
            check_ngrok
            ;;
        *)
            # Full health check
            check_prerequisites
            check_containers
            check_connectivity
            check_agents
            check_log_flow
            check_ngrok
            show_inventory

            print_header "RINGKASAN"
            echo ""
            print_info "Untuk memperbaiki masalah umum: ./scripts/health-check.sh --fix"
            print_info "Untuk install agent ke DVWA:    ./scripts/health-check.sh --agent"
            print_info "Untuk lihat inventori:          ./scripts/health-check.sh --inventory"
            echo ""
            ;;
    esac
}

main "$@"
