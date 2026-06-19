#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"

# Minimal defaults so the file can be safely sourced in tests (real defaults
# are applied later after loading .env).
: "${TECHNITIUM_HOST:=}"
: "${TECHNITIUM_TOKEN:=}"
: "${TECHNITIUM_USER:=}"
: "${TECHNITIUM_PASS:=}"
: "${DOMAIN:=}"
: "${ZONE:=}"
: "${TTL:=}"
: "${UPDATE_IPV4:=}"
: "${UPDATE_IPV6:=}"
: "${CREATE_PTR:=}"
: "${DRYRUN:=}"
: "${VERBOSE:=1}"

# Load a .env-style file (KEY=VALUE) into the environment if present.
load_env_file() {
  local f="$1"
  [[ -f "${f}" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      # Strip surrounding quotes if present
      val="${val%\"}"; val="${val#\"}"
      val="${val%\'}"; val="${val#\'}"
      # Only override if not already set by environment or CLI
      if [[ -z "${!key:-}" ]]; then
        export "${key}=${val}"
      fi
    fi
  done <"${f}"
}

# Warn if sensitive keys are present in the env file when verbosity is high.
warn_sensitive_env() {
  local f="$1"
  [[ -f "${f}" ]] || return 0
  local has_token=false has_pass=false has_user=false
  if grep -E -q '^[[:space:]]*TECHNITIUM_TOKEN=' "${f}"; then has_token=true; fi
  if grep -E -q '^[[:space:]]*TECHNITIUM_PASS=' "${f}"; then has_pass=true; fi
  if grep -E -q '^[[:space:]]*TECHNITIUM_USER=' "${f}"; then has_user=true; fi
  if { [[ "${has_token}" == true ]] || [[ "${has_pass}" == true ]] || [[ "${has_user}" == true ]]; } && [[ "${VERBOSE}" =~ ^[0-9]+$ ]] && (( VERBOSE >= 4 )); then
    >&2 echo -n "WARNING: sensitive variable(s) present in ${f}:"
    [[ "${has_token}" == true ]] && >&2 echo -n ' TECHNITIUM_TOKEN'
    [[ "${has_user}" == true ]] && >&2 echo -n ' TECHNITIUM_USER'
    [[ "${has_pass}" == true ]] && >&2 echo -n ' TECHNITIUM_PASS'
    >&2 echo
    >&2 echo "Ensure ${f} has restrictive permissions (eg. chmod 600) and is not checked into source control."
  fi
}

# Log to stdout when VERBOSE >= level. Usage: log <level> <message...>
log() {
  local level="$1"; shift
  if [[ "${VERBOSE}" =~ ^[0-9]+$ ]] && (( VERBOSE >= level )); then
    echo "$@"
  fi
}

debug() {
  if [[ "${VERBOSE}" =~ ^[0-9]+$ ]] && (( VERBOSE >= 4 )); then
    echo "DEBUG: $*" >&2
  fi
}

warn_sensitive_config() {
  local source="${1:-configuration}"
  local sensitive=()
  [[ -n "${TECHNITIUM_TOKEN:-}" ]] && sensitive+=("TECHNITIUM_TOKEN")
  [[ -n "${TECHNITIUM_USER:-}" ]] && sensitive+=("TECHNITIUM_USER")
  [[ -n "${TECHNITIUM_PASS:-}" ]] && sensitive+=("TECHNITIUM_PASS")

  if [[ ${#sensitive[@]} -eq 0 ]]; then
    return 0
  fi

  if [[ "${VERBOSE}" =~ ^[0-9]+$ ]] && (( VERBOSE >= 4 )); then
    >&2 echo "WARNING: sensitive credential(s) present in ${source}: ${sensitive[*]}"
    >&2 echo "These values may be printed at verbose level above 3. Use caution with secret credentials."
  fi
}

# Print script usage and exit.
usage() {
  cat <<'EOF_USAGE'
Usage: $0 [options]

Options:
  -d, --domain DOMAIN            Full record domain name to update (example.com or host.example.com) (required)
  -z, --zone ZONE                Zone name that contains the record (example.com) (optional)
  -s, --server URL               Technitium API server base URL (default: http://localhost:5380)
  -t, --token TOKEN              Technitium API bearer token (env: TECHNITIUM_TOKEN)
  -u, --user USER                Technitium login username (env: TECHNITIUM_USER)
  -p, --pass PASS                Technitium login password (env: TECHNITIUM_PASS)
      --ttl TTL                  TTL for A/AAAA records (default: 3600) (env: TTL)
      --no-ipv4                  Skip IPv4 update (default: update IPv4)
      --no-ipv6                  Skip IPv6 update (default: update IPv6)
      --ptr                      Update associated PTR record if supported (default: ${CREATE_PTR})
      --dryrun                   Show current public/DNS IPs and planned changes without updating (default: ${DRYRUN})
      --env-file FILE            Load environment variables from FILE (default: ${ENV_FILE})
  -v, --verbose N                Set verbosity level 0 (quiet) .. 5 (max) (default: ${VERBOSE})
      --verbose=N                Same as --verbose N
  -h, --help                     Show this help message

Environment variables (can be provided in the environment or via --env-file):
  TECHNITIUM_HOST (default: http://localhost:5380)
  TECHNITIUM_TOKEN, TECHNITIUM_USER, TECHNITIUM_PASS
  VERBOSE, ENV_FILE, TTL, CREATE_PTR

Examples:
  # Use environment variables and update records
  TECHNITIUM_HOST=http://192.168.1.10:5380 \
    TECHNITIUM_USER=admin TECHNITIUM_PASS=secret \
    $0 -d home.example.com -z example.com

  # Use an env file and verbose debug output
  ./update-technitium-ip.sh --env-file ./creds.env --verbose 5 -d host.example.com -z example.com --dryrun
EOF_USAGE
  exit 1
}

# Print an error message and exit immediately.
fatal() {
  echo "Error: $*" >&2
  exit 1
}

# Verify that required runtime dependencies are installed.
check_dependencies() {
  local missing=()
  
  # Check Bash version >= 4.0
  if [[ ${BASH_VERSINFO[0]:-0} -lt 4 ]]; then
    echo "Error: Bash 4.0 or higher is required (current: ${BASH_VERSION})" >&2
    exit 1
  fi
  
  for cmd in curl jq; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: missing required dependencies: ${missing[*]}" >&2
    echo "Install the missing tools and rerun the script." >&2
    exit 1
  fi
}

# Percent-encode a string for use in API query parameters.
urlencode() {
  jq -nr --arg s "$1" '$s | @uri'
}

# Build a full Technitium API URL with query parameters.
api_url() {
  local path="$1"
  shift
  local q=""
  while [[ $# -gt 0 ]]; do
    local key="$1" value="$2"
    q+="&${key}=$(urlencode "${value}")"
    shift 2
  done
  echo "${TECHNITIUM_HOST%/}/${path}?${q#&}"
}

# Return a bearer token, either from env or by logging in to Technitium.
login_token() {
  if [[ -n "${TECHNITIUM_TOKEN}" ]]; then
    echo "${TECHNITIUM_TOKEN}"
    return
  fi

  [[ -n "${TECHNITIUM_USER}" ]] || fatal "Technitium user not provided"
  [[ -n "${TECHNITIUM_PASS}" ]] || fatal "Technitium password not provided"

  local url
  url=$(api_url "api/user/login" user "${TECHNITIUM_USER}" pass "${TECHNITIUM_PASS}" includeInfo true)
  local response
  if [[ "${VERBOSE}" -ge 4 ]]; then
    echo "DEBUG: GET ${url}" >&2
  fi
  response=$(curl -L -sS --fail --show-error "${url}") || fatal "Failed to login to Technitium API"
  if [[ "${VERBOSE}" -ge 5 ]]; then
    echo "DEBUG: login response:" >&2
    printf '%s' "${response}" | jq -C '.' >&2 || printf '%s\n' "${response}" >&2
  fi
  local token
  token=$(jq -r '.token // .response.token // empty' <<<"${response}")
  [[ -n "${token}" ]] || fatal "Unable to obtain Technitium API token from login response"
  echo "${token}"
}

# Query public IP services and return the current IPv4 or IPv6 address.
get_public_ip() {
  local mode="$1"
  local services
  if [[ "${mode}" == "ipv4" ]]; then
    services=("https://api.ipify.org" "https://ipv4.icanhazip.com" "https://ifconfig.co/ip")
  else
    services=("https://api64.ipify.org" "https://ipv6.icanhazip.com" "https://ifconfig.co/ip")
  fi
  for service in "${services[@]}"; do
    local ip
    debug "Trying ${service} for ${mode} public IP"
    if [[ "${mode}" == "ipv6" ]]; then
      ip=$(curl -6 -sS --fail --show-error --max-time 10 "${service}" 2>/dev/null || true)
    else
      ip=$(curl -4 -sS --fail --show-error --max-time 10 "${service}" 2>/dev/null || true)
    fi
    if [[ -n "${ip//[[:space:]]/}" ]]; then
      ip=$(printf '%s' "${ip}" | tr -d '[:space:]')
      if [[ "${mode}" == "ipv4" && "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
         [[ "${mode}" == "ipv6" && "${ip}" =~ ^[0-9A-Fa-f:]+$ ]]; then
        debug "Detected public ${mode} IP ${ip} from ${service}"
        echo "${ip}"
        return 0
      fi
    fi
  done
  return 1
}

# Fetch matching DNS record values for the requested domain and type.
fetch_record_values() {
  local record_type="$1"
  local url
  local response

  # If a zone was supplied, prefer querying the zone-wide records first so
  # apex / @ / empty-name entries are discovered even when the filtered
  # domain endpoint omits them.
  if [[ -n "${ZONE}" ]]; then
    # Include domain in the zone-wide request; some Technitium API versions
    # require the 'domain' parameter even for zone-scoped queries.
    url=$(api_url "api/zones/records/get" domain "${DOMAIN}" zone "${ZONE}" listZone false)
    if [[ "${VERBOSE}" -ge 4 ]]; then
      echo "DEBUG: GET ${url}" >&2
    fi
    response=$(curl -L --location-trusted -sS --fail --show-error -H "Authorization: Bearer ${TECHNITIUM_TOKEN}" "${url}")
    if [[ "${VERBOSE}" -ge 5 ]]; then
      echo "DEBUG: zone-wide response for ${ZONE}:" >&2
      printf '%s' "${response}" | jq -C '.' >&2 || printf '%s\n' "${response}" >&2
    fi
    if [[ -n "${response//[[:space:]]/}" ]]; then
      jq -r --arg target "$DOMAIN" --arg record_type "$record_type" '
        def stripdot: sub("\\.$"; "");
        (.response.records // [])[]
        | select(.type == $record_type)
        | (.name // "" | stripdot) as $name
        | select($name == $target or $name == "@" or $name == "")
        | . as $r
        | if $record_type == "A" or $record_type == "AAAA" then
            ($r.rData.ipAddress // $r.rData.ipv6Address // $r.rData.address)
          elif $record_type == "CNAME" then
            $r.rData.cname
          else
            $r.rData
          end
        | select(. != null)
      ' <<<"${response}"
      return
    fi
  fi

  # If zone-wide lookup did not return results (or no zone specified), query
  # the API filtered by domain and return any matching records.
  url=$(api_url "api/zones/records/get" domain "${DOMAIN}" ${ZONE:+zone "${ZONE}"} listZone false)
  if [[ "${VERBOSE}" -ge 4 ]]; then
    echo "DEBUG: GET ${url}" >&2
  fi
  response=$(curl -L --location-trusted -sS --fail --show-error -H "Authorization: Bearer ${TECHNITIUM_TOKEN}" "${url}")
  if [[ "${VERBOSE}" -ge 5 ]]; then
    echo "DEBUG: domain-filtered response for ${DOMAIN}:" >&2
    printf '%s' "${response}" | jq -C '.' >&2 || printf '%s\n' "${response}" >&2
  fi
  if [[ -z "${response//[[:space:]]/}" ]]; then
    return 0
  fi

  jq -r --arg target "$DOMAIN" --arg record_type "$record_type" '
    def stripdot: sub("\\.$"; "");
    (.response.records // [])[]
    | select(.type == $record_type)
    | (.name // "" | stripdot) as $name
    | select($name == $target or $name == "@" or $name == "")
    | . as $r
    | if $record_type == "A" or $record_type == "AAAA" then
        ($r.rData.ipAddress // $r.rData.ipv6Address // $r.rData.address)
      elif $record_type == "CNAME" then
        $r.rData.cname
      else
        $r.rData
      end
    | select(. != null)
  ' <<<"${response}"
}

# Update an existing DNS record from an old IP to the current public IP.
perform_update() {
  local type="$1"
  local old_ip="$2"
  local new_ip="$3"
  local url
  if [[ -n "${ZONE}" ]]; then
    url=$(api_url "api/zones/records/update" domain "${DOMAIN}" zone "${ZONE}" type "${type}" ipAddress "${old_ip}" newIpAddress "${new_ip}" ttl "${TTL}" ptr "${CREATE_PTR}")
  else
    url=$(api_url "api/zones/records/update" domain "${DOMAIN}" type "${type}" ipAddress "${old_ip}" newIpAddress "${new_ip}" ttl "${TTL}" ptr "${CREATE_PTR}")
  fi
  if [[ "${VERBOSE}" -ge 4 ]]; then
    echo "DEBUG: POST ${url}" >&2
  fi
  curl -L --location-trusted -sS --fail --show-error -X POST -H "Authorization: Bearer ${TECHNITIUM_TOKEN}" "${url}"
}

# Create a new DNS record for the domain with the current public IP.
perform_add() {
  local type="$1"
  local new_ip="$2"
  local url
  if [[ -n "${ZONE}" ]]; then
    url=$(api_url "api/zones/records/add" domain "${DOMAIN}" zone "${ZONE}" type "${type}" ttl "${TTL}" overwrite true ipAddress "${new_ip}" ptr "${CREATE_PTR}")
  else
    url=$(api_url "api/zones/records/add" domain "${DOMAIN}" type "${type}" ttl "${TTL}" overwrite true ipAddress "${new_ip}" ptr "${CREATE_PTR}")
  fi
  if [[ "${VERBOSE}" -ge 4 ]]; then
    echo "DEBUG: POST ${url}" >&2
  fi
  curl -L --location-trusted -sS --fail --show-error -X POST -H "Authorization: Bearer ${TECHNITIUM_TOKEN}" "${url}"
}

# Show current DNS state and add/update A or AAAA records as needed.
process_record() {
  local type="$1"
  local public_ip="$2"
  local existing
  existing=$(fetch_record_values "${type}" || true)

  if [[ -n "${public_ip}" ]]; then
    log 1 "${type} public IP: ${public_ip}"
  else
    log 1 "${type} public IP: <none>"
  fi

  if [[ -z "${existing}" ]]; then
    log 2 "${type} DNS record: none"
  else
    log 1 "${type} DNS record(s):"
    while IFS= read -r record_ip; do
      [[ -z "${record_ip}" ]] && continue
      log 2 "  - ${record_ip}"
    done <<<"${existing}"
  fi

  if [[ -z "${public_ip}" ]]; then
    log 1 "No public ${type} address available; skipping ${type} update."
    return
  fi

  if [[ -z "${existing}" ]]; then
    if [[ "${DRYRUN}" == true ]]; then
      log 1 "Dry-run: would add ${type} record for ${DOMAIN}"
      log 2 "Dry-run detail: ${type} ${DOMAIN} -> ${public_ip}"
    else
      log 1 "No existing ${type} record found; adding a new record."
      perform_add "${type}" "${public_ip}"
      log 1 "${type} record created: ${DOMAIN} -> ${public_ip}"
    fi
    return
  fi

  local updated=false
  while IFS= read -r old_ip; do
    [[ -z "${old_ip}" ]] && continue
    if [[ "${old_ip}" != "${public_ip}" ]]; then
      if [[ "${DRYRUN}" == true ]]; then
        log 1 "Dry-run: would update ${type} record from ${old_ip} to ${public_ip}"
      else
        log 1 "Updating ${type} record from ${old_ip} to ${public_ip}."
        perform_update "${type}" "${old_ip}" "${public_ip}"
      fi
      updated=true
    else
      log 2 "${type} record already matches ${public_ip}; no update needed"
    fi
  done <<<"${existing}"

  if [[ "${updated}" == false && -n "${existing}" ]]; then
    log 1 "${type} record values already current"
  fi
}

# Parse command-line arguments into script configuration variables.
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--domain)
        DOMAIN="$2"; shift 2;;
      -z|--zone)
        ZONE="$2"; shift 2;;
      -s|--server)
        TECHNITIUM_HOST="$2"; shift 2;;
      -t|--token)
        TECHNITIUM_TOKEN="$2"; shift 2;;
      -u|--user)
        TECHNITIUM_USER="$2"; shift 2;;
      -p|--pass)
        TECHNITIUM_PASS="$2"; shift 2;;
      --ttl)
        TTL="$2"; shift 2;;
      --env-file)
        ENV_FILE="$2"; shift 2;;
      --env-file=*)
        ENV_FILE="${1#*=}"; shift;;
      -v|--verbose)
        VERBOSE="$2"; shift 2;;
      --verbose=*)
        VERBOSE="${1#*=}"; shift;;
      --no-ipv4)
        UPDATE_IPV4=false; shift;;
      --no-ipv6)
        UPDATE_IPV6=false; shift;;
      --ptr)
        CREATE_PTR=true; shift;;
      --dryrun)
        DRYRUN=true; shift;;
      -h|--help)
        usage;;
      *)
        echo "Unknown option: $1" >&2
        usage;;
    esac
  done

  [[ -n "${DOMAIN}" ]] || fatal "Record domain is required (-d/--domain)"
}

# Entry point: validate dependencies, parse args, detect public IPs, and process records.
main() {
  check_dependencies
  # Pre-scan args for --env-file to allow loading before parsing other options
  tmp_args=("$@")
  for ((i=0;i<${#tmp_args[@]};i++)); do
    a="${tmp_args[i]}"
    case "${a}" in
      --env-file=*) ENV_FILE="${a#*=}";;
      --env-file)
        if (( i+1 < ${#tmp_args[@]} )); then ENV_FILE="${tmp_args[i+1]}"; fi
        ;;
    esac
  done
  load_env_file "${ENV_FILE}"
  # Set defaults after loading env file so .env values can override them.
  TECHNITIUM_HOST="${TECHNITIUM_HOST:-http://localhost:5380}"
  TECHNITIUM_TOKEN="${TECHNITIUM_TOKEN:-}"
  TECHNITIUM_USER="${TECHNITIUM_USER:-}"
  TECHNITIUM_PASS="${TECHNITIUM_PASS:-}"
  DOMAIN="${DOMAIN:-}"
  ZONE="${ZONE:-}"
  TTL="${TTL:-3600}"
  UPDATE_IPV4="${UPDATE_IPV4:-true}"
  UPDATE_IPV6="${UPDATE_IPV6:-true}"
  CREATE_PTR="${CREATE_PTR:-false}"
  DRYRUN="${DRYRUN:-false}"
  VERBOSE="${VERBOSE:-1}"
  parse_args "$@"
  warn_sensitive_env "${ENV_FILE}"
  warn_sensitive_config "script configuration"
  TECHNITIUM_TOKEN="$(login_token)"

  # Verbosity level >=4 prints current configuration (sensitive values included).
  if [[ "${VERBOSE}" =~ ^[0-9]+$ ]] && (( VERBOSE >= 4 )); then
    echo "VERBOSE: ${VERBOSE}"
    echo "TECHNITIUM_HOST=${TECHNITIUM_HOST}"
    echo "TECHNITIUM_TOKEN=${TECHNITIUM_TOKEN}"
    echo "TECHNITIUM_USER=${TECHNITIUM_USER}"
    echo "TECHNITIUM_PASS=${TECHNITIUM_PASS}"
    echo "DOMAIN=${DOMAIN}"
    echo "ZONE=${ZONE}"
    echo "TTL=${TTL}"
    echo "UPDATE_IPV4=${UPDATE_IPV4}"
    echo "UPDATE_IPV6=${UPDATE_IPV6}"
    echo "CREATE_PTR=${CREATE_PTR}"
    echo "DRYRUN=${DRYRUN}"
  fi

  local public_ipv4=""
  local public_ipv6=""

  if [[ "${UPDATE_IPV4}" == true ]]; then
    public_ipv4=$(get_public_ip ipv4 || true)
    if [[ -n "${public_ipv4}" ]]; then
      log 1 "Public IPv4 detected: ${public_ipv4}"
    else
      log 1 "Warning: unable to detect public IPv4 address"
    fi
  fi

  if [[ "${UPDATE_IPV6}" == true ]]; then
    public_ipv6=$(get_public_ip ipv6 || true)
    if [[ -n "${public_ipv6}" ]]; then
      log 1 "Public IPv6 detected: ${public_ipv6}"
    else
      log 1 "Warning: unable to detect public IPv6 address"
    fi
  fi

  if [[ -z "${public_ipv4}" && -z "${public_ipv6}" ]]; then
    fatal "No public IP address found for requested family(ies)"
  fi

  if [[ -n "${public_ipv4}" || "${UPDATE_IPV4}" == true ]]; then
    process_record A "${public_ipv4}"
  fi

  if [[ -n "${public_ipv6}" || "${UPDATE_IPV6}" == true ]]; then
    process_record AAAA "${public_ipv6}"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
