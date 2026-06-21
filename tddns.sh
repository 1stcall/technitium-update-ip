#!/bin/bash
set -euo pipefail

# --- DEPENDENCY & BASH VERSION CHECKS ---
REQUIRED_BASH_MAJOR=4
if [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]}" -lt $REQUIRED_BASH_MAJOR ]; then
    echo "Error: This script requires Bash version ${REQUIRED_BASH_MAJOR}.0 or higher." >&2
    echo "Current shell/version: ${SHELL:-Unknown} (Version: ${BASH_VERSION:-Unknown})" >&2
    exit 1
fi

MISSING_DEPS=0
for cmd in curl jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required dependency '$cmd' is not installed." >&2
        MISSING_DEPS=1
    fi
done

if [ $MISSING_DEPS -eq 1 ]; then
    echo "Please install the missing tools (e.g., 'sudo apt install curl jq') and try again." >&2
    exit 1
fi
# ----------------------------------------

# --- CONFIG FILE PATH DETECTION ---
# Default to 'tddns.conf' in the same directory as the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG_FILE="$SCRIPT_DIR/tddns.conf"
CONFIG_FILE=""

# First pass over arguments to look for a custom config file definition (-f or --config)
args=("${@+匀}") # Safe array expansion copy workaround under strict flag constraints
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
    if [[ "${args[i]}" == "-f" || "${args[i]}" == "--config" ]]; then
        if (( i + 1 < ${#args[@]} )); then
            CONFIG_FILE="${args[i+1]}"
        fi
    fi
done

CONFIG_FILE="${CONFIG_FILE:-$DEFAULT_CONFIG_FILE}"

# --- CONFIGURATION LAYER ---
# 1. Load from Configuration File if present
if [ -f "$CONFIG_FILE" ]; then
    # Safely source file stripping carriage returns (windows compatibility)
    while IFS= read -r line || [ -n "$line" ]; do
        cleaned_line=$(echo "$line" | sed 's/\r$//' | xargs)
        if [[ "$cleaned_line" =~ ^TDDNS_[A-Z0-9_]+= ]]; then
            eval "$cleaned_line"
        fi
    done < "$CONFIG_FILE"
fi

# 2. Merge Layer: Env Var beats Config File, Script Default Fallback serves as absolute lowest
DNS_SERVER_URL="${TDDNS_SERVER_URL:-http://192.168.1.100:5380}"
API_TOKEN="${TDDNS_API_TOKEN:-YOUR_API_TOKEN_HERE}"
ZONE="${TDDNS_ZONE:-yourdomain.com}"
DOMAIN="${TDDNS_DOMAIN:-yourdomain.com}"
TTL="${TDDNS_TTL:-3600}"
UPDATE_PTR="${TDDNS_UPDATE_PTR:-false}"
VERBOSE="${TDDNS_VERBOSE:-false}"
CHECK_ONLY="${TDDNS_CHECK_ONLY:-false}"
# -----------------------------------------------------------------------

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --config FILE      Path to config file (default: ./tddns.conf)"
    echo "  -s, --server URL       Technitium server URL (e.g., http://192.168.1.100:5380)"
    echo "  -t, --token TOKEN      Technitium API Token"
    echo "  -z, --zone ZONE        DNS Zone name (e.g., yourdomain.com)"
    echo "  -d, --domain DOMAIN    Specific FQDN or Apex Domain to update"
    echo "  -l, --ttl SECONDS      Time-to-live value (default: 3600)"
    echo "  -c, --check-only       Dry-run mode. Check configuration without updating."
    echo "  -p, --ptr              Natively tell Technitium to generate/update matching PTR record."
    echo "  -v, --verbose          Debug mode. Echoes prettified API responses to stderr."
    echo "  -h, --help             Show this help menu"
    echo ""
    echo "Environment Variables / Config File options (prefixed with TDDNS_):"
    echo "  TDDNS_SERVER_URL, TDDNS_API_TOKEN, TDDNS_ZONE, TDDNS_DOMAIN, TDDNS_TTL,"
    echo "  TDDNS_UPDATE_PTR, TDDNS_VERBOSE, TDDNS_CHECK_ONLY"
    echo ""
    exit 0
}

# 3. Parse Command Line Arguments (Will overwrite config file and env vars)
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--config)     CONFIG_FILE="$2"; shift 2 ;;
        -s|--server)     DNS_SERVER_URL="$2"; shift 2 ;;
        -t|--token)      API_TOKEN="$2"; shift 2 ;;
        -z|--zone)       ZONE="$2"; shift 2 ;;
        -d|--domain)     DOMAIN="$2"; shift 2 ;;
        -l|--ttl)        TTL="$2"; shift 2 ;;
        -c|--check-only) CHECK_ONLY=true; shift ;;
        -p|--ptr)        UPDATE_PTR=true; shift ;;
        -v|--verbose)    VERBOSE=true; shift ;;
        -h|--help)       show_help ;;
        *) echo "Unknown option: $1" >&2; show_help ;;
    esac
done

# Apex Normalization Check
DOMAIN=$(echo "$DOMAIN" | sed 's/^@\.//; s/^@//')

if [ "$CHECK_ONLY" = true ]; then
    echo "=== RUNNING IN CHECK-ONLY MODE ==="
fi

if [ "$VERBOSE" = true ]; then
    echo "=== DEBUG MODE ACTIVE (Prettified API responses sent to stderr) ===" >&2
fi

# Function to handle a specific record type
process_record() {
    local RECORD_TYPE=$1
    local CURRENT_IP=$2

    if [ -z "$CURRENT_IP" ]; then
        echo "Skipping $RECORD_TYPE: No valid public IP provided."
        return 1
    fi

    # 1. Fetch existing record from Technitium
    RECORD_RESOLVE=$(curl -s "$DNS_SERVER_URL/api/zones/records/get?token=$API_TOKEN&domain=$DOMAIN&type=$RECORD_TYPE")
    
    # Debug: Output prettified JSON payload using jq to stderr
    if [ "$VERBOSE" = true ]; then
        echo -e "\n[DEBUG] Prettified GET response for $RECORD_TYPE:" >&2
        echo "$RECORD_RESOLVE" | jq . >&2
    fi

    # Robust Filter: Scans the array and matches by record type explicitly (Both A and AAAA use .ipAddress inside rData)
    EXISTING_IP=$(echo "$RECORD_RESOLVE" | jq -r --arg type "$RECORD_TYPE" '.response.records[] | select(.type==$type) | .rData.ipAddress // empty' | head -n 1 || echo "")

    # 2. Compare IPs
    if [ "$CURRENT_IP" == "$EXISTING_IP" ]; then
        echo "[MATCH] $RECORD_TYPE record matches Technitium ($EXISTING_IP). No update required."
        return 0
    elif [ -z "$EXISTING_IP" ]; then
        echo "[MISSING] No existing $RECORD_TYPE record found. It will be created."
    else
        echo "[MISMATCH] Current $RECORD_TYPE is $CURRENT_IP, but Technitium has $EXISTING_IP."
    fi

    # 3. Guard clause for check-only mode
    if [ "$CHECK_ONLY" = true ]; then
        echo "--> [SKIPPED] Check-only mode active. No changes made."
        return 0
    fi

    # 4. Handle Native PTR parameters if requested
    local PTR_PARAMS=()
    if [ "$UPDATE_PTR" = true ]; then
        echo "Requesting native PTR updates alongside $RECORD_TYPE record..."
        PTR_PARAMS=("-d" "ptr=true" "-d" "createPtrZone=true")
    fi

    if [ -z "$EXISTING_IP" ]; then
        echo "Creating new Technitium $RECORD_TYPE record..."
    else
        echo "Updating existing Technitium $RECORD_TYPE record (Overwriting $EXISTING_IP)..."
    fi

    # 5. Push request to Technitium using the robust Add+Overwrite strategy
    UPDATE_RESPONSE=$(curl -s -X POST "$DNS_SERVER_URL/api/zones/records/add" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "token=$API_TOKEN" \
        -d "domain=$DOMAIN" \
        -d "type=$RECORD_TYPE" \
        -d "ttl=$TTL" \
        -d "ipAddress=$CURRENT_IP" \
        -d "overwrite=true" \
        "${PTR_PARAMS[@]}")

    # Debug: Output prettified add response to stderr
    if [ "$VERBOSE" = true ]; then
        echo -e "\n[DEBUG] Prettified POST (add?overwrite=true) response for $RECORD_TYPE:" >&2
        echo "$UPDATE_RESPONSE" | jq . >&2
    fi

    # 6. Verify success using jq string checking
    STATUS=$(echo "$UPDATE_RESPONSE" | jq -r '.status' || echo "error")

    if [ "$STATUS" == "ok" ]; then
        echo "--> [SUCCESS] Managed $RECORD_TYPE record to $CURRENT_IP!"
    else
        echo "--> [FAILED] Server response status was not 'ok'."
        if [ "$VERBOSE" = false ]; then
            echo "$UPDATE_RESPONSE" | jq .
        fi
    fi
}

# --- MAIN EXECUTION ---
if [ "$DOMAIN" == "$ZONE" ]; then
    echo "Targeting Apex Domain: $DOMAIN (Zone: $ZONE, TTL: $TTL)"
else
    echo "Targeting Subdomain: $DOMAIN (Zone: $ZONE, TTL: $TTL)"
fi

# Fetch current Public IPs (Guarded against lookup drops using || true)
PUBLIC_IPV4=$(curl -4 -s https://icanhazip.com 2>/dev/null | tr -d '[:space:]' || echo "")
echo "Public IPv4 Detected: ${PUBLIC_IPV4:-None}"

PUBLIC_IPV6=$(curl -6 -s https://icanhazip.com 2>/dev/null | tr -d '[:space:]' || echo "")
echo "Public IPv6 Detected: ${PUBLIC_IPV6:-None}"

echo "------------------------------------------------"

# Process IPv4 / A Record
if [ -n "$PUBLIC_IPV4" ]; then
    process_record "A" "$PUBLIC_IPV4"
else
    echo "Warning: No public IPv4 address detected. Skipping A record."
fi

echo "------------------------------------------------"

# Process IPv6 / AAAA Record
if [ -n "$PUBLIC_IPV6" ]; then
    process_record "AAAA" "$PUBLIC_IPV6"
else
    echo "Warning: No public IPv6 address detected. Skipping AAAA record."
fi