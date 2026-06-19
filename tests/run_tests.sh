#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$ROOT/tests/mocks:$PATH"

echo "Running unit tests for update-technitium-ip.sh"

# Load script (won't execute main because of guard)
# shellcheck disable=SC1090
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

# Test: warn_sensitive_env prints warning when VERBOSE>=5
VERBOSE=5
cat > /tmp/sens.env <<'EOF'
TECHNITIUM_TOKEN=abc
TECHNITIUM_USER=me
EOF
warn_out=$(mktemp)
if warn_sensitive_env /tmp/sens.env 2>"$warn_out"; then :; fi
if ! grep -q "TECHNITIUM_TOKEN" "$warn_out"; then echo "warn_sensitive_env missing token"; cat "$warn_out"; exit 1; fi
if ! grep -q "TECHNITIUM_USER" "$warn_out"; then echo "warn_sensitive_env missing user"; cat "$warn_out"; exit 1; fi
rm -f "$warn_out"

# Test: fetch_record_values uses mocked curl and returns A record
TECHNITIUM_TOKEN=""
TECHNITIUM_USER=testuser
TECHNITIUM_PASS=testpass
DOMAIN=example.com
ZONE=example.com
# call fetch_record_values A
out=$(fetch_record_values A)
if [[ "$out" != "1.2.3.4" ]]; then echo "fetch_record_values A returned '$out'"; exit 1; fi

# Test: fetch_record_values AAAA
out6=$(fetch_record_values AAAA)
if [[ "$out6" != "::1" ]]; then echo "fetch_record_values AAAA returned '$out6'"; exit 1; fi

echo "All tests passed." 
