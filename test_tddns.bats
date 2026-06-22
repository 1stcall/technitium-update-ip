#!/usr/bin/env bats

setup() {
    ORIGINAL_PATH="$PATH"
    
    TEST_TEMP_DIR="$(mktemp -d)"
    SCRIPT_UNDER_TEST="./tddns.sh"
    MOCK_CONFIG="$TEST_TEMP_DIR/tddns.conf"
    
    MOCK_BIN_DIR="$TEST_TEMP_DIR/bin"
    mkdir -p "$MOCK_BIN_DIR"
    
    export PATH="$MOCK_BIN_DIR:$PATH"
    
    export TDDNS_SERVER_URL="http://mock-dns:5380"
    export TDDNS_API_TOKEN="mock-token"
}

teardown() {
    export PATH="$ORIGINAL_PATH"
    # Clean up any exported mock functions so they don't leak
    unset -f command 2>/dev/null || true
    rm -rf "$TEST_TEMP_DIR"
}

# --- TEST CASES ---

@test "Fail gracefully if dependency 'jq' is missing" {
    # To mock a shell builtin like 'command', we define a function 
    # and export it so the child bash script inherits it.
    command() {
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "jq" ]; then
            return 1 # Pretend 'jq' doesn't exist
        fi
        builtin command "$@"
    }
    export -f command

    run bash tddns.sh
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Required dependency" ]]
}

@test "Parse and respect configuration file parameters" {
    cat <<EOF > "$MOCK_CONFIG"
TDDNS_SERVER_URL=http://config-file-dns:5380
TDDNS_API_TOKEN=config-token
TDDNS_ZONE=configzone.com
TDDNS_DOMAIN=configzone.com
EOF

    cat <<EOF > "$MOCK_BIN_DIR/curl"
#!/bin/bash
if [[ "\$*" =~ "icanhazip.com" ]]; then
    echo "1.2.3.4"
else
    echo '{"status":"ok","response":{"records":[{"type":"A","rData":{"ipAddress":"1.2.3.4"}}]}}'
fi
EOF
    chmod +x "$MOCK_BIN_DIR/curl"

    run bash tddns.sh -f "$MOCK_CONFIG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Targeting Apex Domain: configzone.com" ]]
}

@test "CLI Flags take absolute precedence over Environment Variables" {
    export TDDNS_DOMAIN="env-domain.com"
    
    cat <<EOF > "$MOCK_BIN_DIR/curl"
#!/bin/bash
if [[ "\$*" =~ "icanhazip.com" ]]; then
    echo "1.2.3.4"
else
    echo '{"status":"ok","response":{"records":[{"type":"A","rData":{"ipAddress":"1.2.3.4"}}]}}'
fi
EOF
    chmod +x "$MOCK_BIN_DIR/curl"

    # Pass matching zone and domain to trigger the Apex Domain string output safely
    run bash tddns.sh -z "cli-override.com" -d "cli-override.com"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Targeting Apex Domain: cli-override.com" ]]
    [[ ! "$output" =~ "env-domain.com" ]]
}

@test "Skip updates if local public IP matches Technitium registry record ([MATCH])" {
    cat <<EOF > "$MOCK_BIN_DIR/curl"
#!/bin/bash
if [[ "\$*" =~ "-4" ]]; then
    echo "192.0.2.1"
elif [[ "\$*" =~ "-6" ]]; then
    echo "2001:db8::1"
else
    echo '{"status":"ok","response":{"records":[{"type":"A","rData":{"ipAddress":"192.0.2.1"}},{"type":"AAAA","rData":{"ipAddress":"2001:db8::1"}}]}}'
fi
EOF
    chmod +x "$MOCK_BIN_DIR/curl"

    run bash tddns.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "[MATCH] A record matches Technitium" ]]
    [[ "$output" =~ "[MATCH] AAAA record matches Technitium" ]]
}

@test "Trigger update action on IP delta mismatch ([MISMATCH])" {
    cat <<EOF > "$MOCK_BIN_DIR/curl"
#!/bin/bash
if [[ "\$*" =~ "-4" ]]; then
    echo "1.1.1.1"
elif [[ "\$*" =~ "-6" ]]; then
    echo ""
    exit 0
elif [[ "\$*" =~ "/api/zones/records/get" ]]; then
    echo '{"status":"ok","response":{"records":[{"type":"A","rData":{"ipAddress":"2.2.2.2"}}]}}'
elif [[ "\$*" =~ "/api/zones/records/add" ]]; then
    echo '{"status":"ok"}'
fi
EOF
    chmod +x "$MOCK_BIN_DIR/curl"

    run bash tddns.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "[MISMATCH] Current A is 1.1.1.1, but Technitium has 2.2.2.2" ]]
    [[ "$output" =~ "--> [SUCCESS] Managed A record to 1.1.1.1!" ]]
}

@test "Guard clause blocks modifications when running in Check-Only mode" {
    cat <<EOF > "$MOCK_BIN_DIR/curl"
#!/bin/bash
if [[ "\$*" =~ "-4" ]]; then
    echo "1.1.1.1"
else
    echo '{"status":"ok","response":{"records":[{"type":"A","rData":{"ipAddress":"2.2.2.2"}}]}}'
fi
EOF
    chmod +x "$MOCK_BIN_DIR/curl"

    run bash tddns.sh --check-only
    [ "$status" -eq 0 ]
    [[ "$output" =~ "=== RUNNING IN CHECK-ONLY MODE ===" ]]
    [[ "$output" =~ "--> [SKIPPED] Check-only mode active." ]]
}