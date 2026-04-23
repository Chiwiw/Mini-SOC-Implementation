#!/usr/bin/env python3
"""
============================================================
custom-otx.py - AlienVault OTX Threat Intelligence Integration
SOC Project | Infrastructure Builder
============================================================

Cara penggunaan:
1. Analyst mengisi OTX_API_KEY di file .env
2. Script ini otomatis dipanggil oleh Wazuh Manager saat ada alert level >= 7
3. Script akan query OTX untuk cek apakah IP attacker ada di threat feed

Lokasi di container: /var/ossec/integrations/custom-otx.py
Permission: chmod 750 /var/ossec/integrations/custom-otx.py
Owner: chown root:wazuh /var/ossec/integrations/custom-otx.py
============================================================
"""

import sys
import json
import urllib.request
import urllib.error
import logging
import os
from datetime import datetime

# ============================================================
# KONFIGURASI
# ============================================================

# API Key OTX - Diisi oleh Analyst
# Bisa juga dibaca dari environment variable untuk keamanan
OTX_API_KEY = os.environ.get("OTX_API_KEY", "PASTE_YOUR_OTX_API_KEY_HERE")
OTX_BASE_URL = "https://otx.alienvault.com/api/v1/indicators"

# Log file untuk debugging
LOG_FILE = "/var/ossec/logs/integrations/custom-otx.log"

# ============================================================
# SETUP LOGGING
# ============================================================

os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stderr)
    ]
)
logger = logging.getLogger("custom-otx")


# ============================================================
# FUNGSI UTAMA
# ============================================================

def query_otx_ip(ip_address: str) -> dict:
    """
    Query OTX untuk mengecek reputasi IP address.
    Return: dict dengan info threat intel dari OTX
    """
    url = f"{OTX_BASE_URL}/IPv4/{ip_address}/general"
    headers = {
        "X-OTX-API-KEY": OTX_API_KEY,
        "Content-Type": "application/json"
    }

    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode("utf-8"))
            return data
    except urllib.error.HTTPError as e:
        logger.error(f"OTX HTTP Error for {ip_address}: {e.code} {e.reason}")
        return {}
    except urllib.error.URLError as e:
        logger.error(f"OTX URL Error for {ip_address}: {e.reason}")
        return {}
    except Exception as e:
        logger.error(f"Unexpected error querying OTX for {ip_address}: {e}")
        return {}


def query_otx_domain(domain: str) -> dict:
    """
    Query OTX untuk mengecek reputasi domain.
    """
    url = f"{OTX_BASE_URL}/domain/{domain}/general"
    headers = {"X-OTX-API-KEY": OTX_API_KEY}

    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception as e:
        logger.error(f"Error querying OTX domain {domain}: {e}")
        return {}


def parse_otx_response(otx_data: dict, indicator: str) -> dict:
    """
    Parse response OTX menjadi format yang bersih untuk alert.
    """
    if not otx_data:
        return {"found": False, "indicator": indicator}

    pulse_count = otx_data.get("pulse_info", {}).get("count", 0)
    pulses = otx_data.get("pulse_info", {}).get("pulses", [])

    # Ambil nama pulse (threat campaign) yang relevan
    pulse_names = [p.get("name", "") for p in pulses[:5]]  # Max 5

    result = {
        "found": pulse_count > 0,
        "indicator": indicator,
        "pulse_count": pulse_count,
        "threat_score": min(pulse_count * 10, 100),  # Normalisasi ke 0-100
        "pulses": pulse_names,
        "country": otx_data.get("country_name", "Unknown"),
        "asn": otx_data.get("asn", "Unknown"),
        "queried_at": datetime.utcnow().isoformat() + "Z"
    }

    return result


def send_alert(alert_data: dict, otx_result: dict):
    """
    Kirim hasil enrichment ke stdout (dibaca Wazuh Manager).
    """
    enriched_alert = {
        "integration": "AlienVault_OTX",
        "otx": otx_result,
        "original_alert": alert_data
    }

    # Wazuh membaca output dari stdout
    print(json.dumps(enriched_alert))
    sys.stdout.flush()

    if otx_result.get("found"):
        logger.warning(
            f"THREAT INTEL HIT! IP {otx_result['indicator']} found in {otx_result['pulse_count']} OTX pulses. "
            f"Threat Score: {otx_result['threat_score']}/100. "
            f"Campaigns: {', '.join(otx_result['pulses'][:3])}"
        )
    else:
        logger.info(f"IP {otx_result['indicator']} - No OTX threat intel found.")


# ============================================================
# ENTRY POINT
# ============================================================

def main():
    """
    Wazuh memanggil script ini dengan argumen:
    sys.argv[1] = path ke file JSON alert sementara
    sys.argv[2] = API key (dari konfigurasi ossec.conf)
    sys.argv[3] = hook_url (opsional)
    """

    # Validasi argumen
    if len(sys.argv) < 2:
        logger.error("Usage: custom-otx.py <alert_file> [api_key] [hook_url]")
        sys.exit(1)

    alert_file = sys.argv[1]

    # Override API key dari argumen jika ada
    if len(sys.argv) >= 3 and sys.argv[2] != "":
        api_key_override = sys.argv[2]
        if api_key_override != "PASTE_YOUR_OTX_API_KEY_HERE":
            global OTX_API_KEY
            OTX_API_KEY = api_key_override

    # Validasi API key
    if OTX_API_KEY == "PASTE_YOUR_OTX_API_KEY_HERE" or not OTX_API_KEY:
        logger.error("OTX API Key belum dikonfigurasi! Isi di file .env atau ossec.conf.")
        sys.exit(1)

    # Baca alert dari file
    try:
        with open(alert_file, "r") as f:
            alert_data = json.load(f)
    except Exception as e:
        logger.error(f"Gagal membaca alert file {alert_file}: {e}")
        sys.exit(1)

    logger.info(f"Processing alert: {alert_data.get('id', 'unknown')} | Rule: {alert_data.get('rule', {}).get('id', 'unknown')}")

    # Ekstrak IP source dari alert
    src_ip = (
        alert_data.get("data", {}).get("srcip") or
        alert_data.get("data", {}).get("src_ip") or
        alert_data.get("agent", {}).get("ip")
    )

    if not src_ip:
        logger.warning("Tidak ada source IP di alert, skip OTX query.")
        sys.exit(0)

    # Skip IP lokal / private
    private_ranges = ("10.", "172.", "192.168.", "127.", "0.", "::1")
    if any(src_ip.startswith(r) for r in private_ranges):
        logger.info(f"IP {src_ip} adalah IP private, skip OTX query.")
        sys.exit(0)

    # Query OTX
    logger.info(f"Querying OTX for IP: {src_ip}")
    otx_raw = query_otx_ip(src_ip)
    otx_result = parse_otx_response(otx_raw, src_ip)

    # Kirim hasil ke Wazuh
    send_alert(alert_data, otx_result)


if __name__ == "__main__":
    main()
