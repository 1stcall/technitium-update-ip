# Technitium Dynamic DNS (DDNS) Updater Script

## Description
A production-hardened Bash script to automatically monitor and update your public IPv4 (`A`) and IPv6 (`AAAA`) records using the **Technitium DNS Server API**. 

Featuring native Reverse DNS (`PTR`) automation, multi-layered configuration management (CLI flags, environment variables, and config files), and comprehensive error safety handling.

## DDNS Features

* **Dual-Stack Execution:** Updates both `A` (IPv4) and `AAAA` (IPv6) records automatically.
* **Robust Hardening:** Implements strict `set -euo pipefail` error tracing to ensure clean terminations and execution safety.
* **Smart Overwrites:** Utilizes Technitium's robust `/records/add` endpoint with `overwrite=true` to safely synchronize entries even if state records are missing or corrupted.
* **Native PTR Automation:** Features standard `-p` support to request native reverse DNS allocation updates via Technitium (`ptr=true`, `createPtrZone=true`).
* **Layered Precedence Configuration:** Respects configurations in the following priority sequence:
    Command Line Flags -> Environment Variables -> Config File -> Defaults

## Changelog
0.1.0 Initial trial of concept coded exclusivly using chatgpt.  
0.2.0 Initial trial using gemini and my own tweeks.  
0.2.1 Updated readme with changelog and versioning.
0.3.0 Added instalation script.

---

## Prerequisites and Dependencies

### Runtime Dependencies
To use this script in production, you only need standard lightweight CLI networking utilities:
* **Bash v4.0** or newer
* `curl` (for making API calls and public IP lookups)
* `jq` (for parsing JSON responses cleanly)

To install runtime dependencies on Debian/Ubuntu:
```bash
sudo apt update && sudo apt install curl jq -y
```

### Development and Testing Dependencies
If you are modifying the script or running the unit tests locally, you will need the following automated testing frameworks:
* **BATS (Bash Automated Testing System):** An industry-standard TAP-compliant testing framework for Bash.
* `bats-assert / bats-support (Optional):` Libraries for enhanced assertions.

To install development dependencies:
```bash
# Ubuntu/Debian
sudo apt install bats

# macOS
brew install bats-core
```

---

## Installation
To install using defaults:
```bash
curl https://raw.githubusercontent.com/1stcall/technitium-update-ip/refs/heads/main/install.sh | sudo bash
```

---

## Configuration Setup

You can configure the behavior of the updater script in three different ways:

### 1. Configuration File (Recommended)
Create a file named `tddns.conf` in the same directory as the script. All parameters inside must be prefixed with `TDDNS_`:

```ini
# tddns.conf
TDDNS_SERVER_URL=http://192.168.1.100:5380
TDDNS_API_TOKEN=your_secret_api_token_here
TDDNS_ZONE=example.com
TDDNS_DOMAIN=example.com
TDDNS_TTL=3600
```

### 2. Environment Variables
Perfect for custom system variables, shell orchestration profiles, or containers:

```bash
export TDDNS_API_TOKEN="your_secret_api_token_here"
export TDDNS_DOMAIN="home.example.com"
```

### 3. Command Line Arguments
Flags always win and overwrite values provided by environment profiles or configurations:

| Short Flag | Long Flag | Description |
| :--- | :--- | :--- |
| `-f` | `--config` | Custom path to configuration file (Default: `./tddns.conf`) |
| `-s` | `--server` | Technitium Server Base URL |
| `-t` | `--token` | Technitium API Token with Zone Modify rights |
| `-z` | `--zone` | Targeted Parent DNS Zone name |
| `-d` | `--domain` | Domain name string or FQDN to be updated |
| `-l` | `--ttl` | Record cache lifetime context (Default: `3600`) |
| `-p` | `--ptr` | Instruct Technitium to generate/update corresponding PTR record |
| `-c` | `--check-only` | Run in dry-run/check-only mode without executing API mutations |
| `-v` | `--verbose` | Output debug traces and prettified raw JSON responses |

---

## Usage Examples

Make the script executable before running it:
```bash
chmod +x tddns.sh
```

**Run using local config file configuration:**
```bash
./tddns.sh
```

**Perform a dry run with verbose logging to test setups:**
```bash
./tddns.sh --check-only --verbose
```

---

## How to Test

The project includes an automated suite in `test_tddns.bats` that tests the logic without hitting your actual Technitium DNS server or leaking tokens. It uses virtual sandboxes and mock binaries to simulate network state changes, matching/mismatching registry states, and missing runtime configurations.

To run the automated suite:
```bash
bats test_tddns.bats
```

### What the Test Suite Checks:
1. **Pristine Error Isolation:** Validates that the `set -euo pipefail` environment handles system dependencies safely.
2. **Precedence Assertions:** Verifies that a CLI argument reliably wins over file and environment profiles.
3. **State Engine Control:** Confirms that matching IPs gracefully skip the API loop, while an IP change safely forces a Technitium `/records/add` call with `overwrite=true`.

---

## Automating with Cron

To maintain a persistent sync pattern with your external infrastructure IPs, automate execution via a cron schedule profile.

1. Open your system crontab scheduler:
   ```bash
   crontab -e
   ```
2. Append a runtime statement. For example, to evaluate changes every **5 minutes**:
   ```text
   */5 * * * * /path/to/tddns.sh >> /var/log/tddns.log 2>&1
   ```

---

## License

This project is open-source software licensed under the **MIT License**.

```text
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
