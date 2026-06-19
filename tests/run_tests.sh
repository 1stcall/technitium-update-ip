#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$ROOT/tests/mocks:$PATH"

echo "Running unit tests for update-technitium-ip.sh"

# Load script (won't execute main because of guard)
# shellcheck disable=SC1091
source "$ROOT/update-technitium-ip.sh"

# Test: load_env_file sets variables
cat > /tmp/test.env <<'EOF'
FOO=bar
TECHNITIUM_USER=testuser
TECHNITIUM_PASS=passw
EOF

unset FOO TECHNITIUM_USER TECHNITIUM_PASS
load_env_file /tmp/test.env
if [[ "${FOO}" != "bar" ]]; then echo "load_env_file failed"; exit 1; fi
if [[ "${TECHNITIUM_USER}" != "testuser" ]]; then echo "load_env_file user failed"; exit 1; fi

# Test: warn_sensitive_env prints warning when VERBOSE>=4
VERBOSE=4
cat > /tmp/sens.env <<'EOF'
TECHNITIUM_TOKEN=abc
TECHNITIUM_USER=me
EOF
warn_out=$(mktemp)
if warn_sensitive_env /tmp/sens.env 2>"$warn_out"; then :; fi
if ! grep -q "TECHNITIUM_TOKEN" "$warn_out"; then echo "warn_sensitive_env missing token"; cat "$warn_out"; exit 1; fi
if ! grep -q "TECHNITIUM_USER" "$warn_out"; then echo "warn_sensitive_env missing user"; cat "$warn_out"; exit 1; fi
rm -f "$warn_out"

# Test: verbose >=4 warns when credentials are shown and prints config values
VERBOSE=4
cat > /tmp/cred.env <<'EOF'
TECHNITIUM_TOKEN=secret-token
TECHNITIUM_USER=admin
TECHNITIUM_PASS=secret-pass
DOMAIN=example.com
ZONE=example.com
EOF
unset TECHNITIUM_USER TECHNITIUM_PASS TECHNITIUM_TOKEN DOMAIN ZONE UPDATE_IPV4 UPDATE_IPV6 DRYRUN ENV_FILE
ENV_FILE=/tmp/cred.env
export DRYRUN=true
export UPDATE_IPV4=true
export UPDATE_IPV6=false
get_public_ip() { echo "1.2.3.4"; }
main_out=$(mktemp)
main_err=$(mktemp)
if main --env-file "$ENV_FILE" -d example.com -z example.com --dryrun >"$main_out" 2>"$main_err"; then :; else echo "main verbose credential warning test failed"; cat "$main_err"; exit 1; fi
if ! grep -q "WARNING: sensitive variable(s) present in /tmp/cred.env" "$main_err"; then echo "missing sensitive credential warning"; cat "$main_err"; exit 1; fi
if ! grep -q "WARNING: sensitive credential(s) present in script configuration" "$main_err"; then echo "missing script configuration warning"; cat "$main_err"; exit 1; fi
if ! grep -q "TECHNITIUM_TOKEN=secret-token" "$main_out"; then echo "config token not printed at verbose >=4"; cat "$main_out"; exit 1; fi
if ! grep -q "TECHNITIUM_PASS=secret-pass" "$main_out"; then echo "config pass not printed at verbose >=4"; cat "$main_out"; exit 1; fi
rm -f "$main_out" "$main_err"

# Test: log only prints when VERBOSE is high enough
export VERBOSE=1
if log 2 "should not print" | grep -q .; then echo "log level filtering failed"; exit 1; fi
export VERBOSE=3
if [[ "$(log 2 "should print")" != "should print" ]]; then echo "log output failed"; exit 1; fi

# Test: fetch_record_values uses mocked curl and returns A record
export TECHNITIUM_TOKEN=""
export TECHNITIUM_USER=testuser
export TECHNITIUM_PASS=testpass
export DOMAIN=example.com
export ZONE=example.com
# call fetch_record_values A
out=$(fetch_record_values A)
if [[ "$out" != "1.2.3.4" ]]; then echo "fetch_record_values A returned '$out'"; exit 1; fi

# Test: fetch_record_values AAAA
out6=$(fetch_record_values AAAA)
if [[ "$out6" != "::1" ]]; then echo "fetch_record_values AAAA returned '$out6'"; exit 1; fi

echo "All tests passed." 
