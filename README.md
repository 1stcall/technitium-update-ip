# Technitium DNS Update IP

A Bash script to automatically update Technitium DNS server records with your current public IP addresses (IPv4 and IPv6).

## Features

- **Automatic IP detection**: Queries multiple public IP services for current IPv4 and IPv6 addresses
- **Dry-run mode**: Preview changes without updating DNS records
- **Verbosity levels**: Control output verbosity from 0=silent to 5=debug with HTTP requests and responses
- **Environment variables**: Set all parameters via CLI, environment, or `.env` file
- **Dependency checks**: Verifies required tools (`curl`, `jq` and `Bash 4.0+`) are installed
- **Sensitive data warnings**: Alerts when credentials will be displayed at high verbosity

## Requirements

- Bash 4.0+
- `curl`
- `jq`
- Access to a Technitium DNS server with API enabled

## Installation

Clone the repository and make the script executable:

```bash
git clone git@github.com:1stcall/technitium-update-ip.git
cd technitium-update-ip
chmod +x update-technitium-ip.sh
```

## Usage

### Basic Usage

Update DNS record with current public IP:

```bash
./update-technitium-ip.sh \
  -d example.com \
  -z example.com \
  -s http://dns-server:5380 \
  -u admin \
  -p password
```

### Dry-Run (Preview Changes)

```bash
./update-technitium-ip.sh \
  -d example.com \
  -z example.com \
  -s http://dns-server:5380 \
  -u admin \
  -p password \
  --dryrun
```

### Using Environment Variables

```bash
export TECHNITIUM_HOST=http://dns-server:5380
export TECHNITIUM_USER=admin
export TECHNITIUM_PASS=password
export DOMAIN=example.com
export ZONE=example.com

./update-technitium-ip.sh
```

### Using .env File

Create a `.env` file:

```
TECHNITIUM_HOST=http://dns-server:5380
TECHNITIUM_USER=admin
TECHNITIUM_PASS=password
DOMAIN=example.com
ZONE=example.com
VERBOSE=1
```

Run the script:

```bash
./update-technitium-ip.sh --env-file .env
```

### Help

```bash
./update-technitium-ip.sh --help
```

## Options

| Option | Env Var | Description |
|--------|---------|-------------|
| `-d, --domain DOMAIN` | `DOMAIN` | Full record domain name (required) |
| `-z, --zone ZONE` | `ZONE` | Zone name containing the record (optional) |
| `-s, --server URL` | `TECHNITIUM_HOST` | API server base URL (default: http://localhost:5380) |
| `-t, --token TOKEN` | `TECHNITIUM_TOKEN` | Bearer token (instead of user/pass) |
| `-u, --user USER` | `TECHNITIUM_USER` | Login username |
| `-p, --pass PASS` | `TECHNITIUM_PASS` | Login password |
| `--ttl TTL` | `TTL` | TTL for records (default: 3600) |
| `--no-ipv4` | `UPDATE_IPV4` | Skip IPv4 update |
| `--no-ipv6` | `UPDATE_IPV6` | Skip IPv6 update |
| `--ptr` | `CREATE_PTR` | Update PTR record if supported |
| `--dryrun` | `DRYRUN` | Show changes without updating |
| `--env-file FILE` | `ENV_FILE` | Load variables from file (default: .env) |
| `-v, --verbose N` | `VERBOSE` | Verbosity level 0-5 (default: 1) |
| `-h, --help` | | Show help message |

## Verbosity Levels

| Level | Output |
|-------|--------|
| 0 | Silent; normal progress logging is suppressed |
| 1 | Standard messages and summary actions (default) |
| 2 | Additional detail such as current DNS records and dry-run specifics |
| 3 | Extended info for more verbose workflows |
| 4 | Additional operational detail |
| 5 | Full debug output, including API request/response traces and configuration |

**Warning**: Verbosity level 4 or above prints sensitive values from the script configuration, so use it carefully with credentials in a `.env` file.

## Examples

### Update a subdomain with custom TTL

```bash
./update-technitium-ip.sh \
  -d host.example.com \
  -z example.com \
  -s http://dns-server:5380 \
  -u admin -p password \
  --ttl 600
```

### Full verbosity with HTTP debugging

```bash
./update-technitium-ip.sh \
  -d example.com \
  -z example.com \
  -s http://dns-server:5380 \
  -u admin -p password \
  --verbose 5
```

### Only update IPv4, skip IPv6

```bash
./update-technitium-ip.sh \
  -d example.com \
  -z example.com \
  -s http://dns-server:5380 \
  -u admin -p password \
  --no-ipv6
```

### Use token-based authentication

```bash
./update-technitium-ip.sh \
  -d example.com \
  -z example.com \
  -s http://dns-server:5380 \
  -t your-api-token
```

## Scheduling with Cron

Update DNS record every 5 minutes:

```cron
*/5 * * * * /home/user/technitium-update-ip/update-technitium-ip.sh --env-file /home/user/technitium-update-ip/.env >> /var/log/technitium-update.log 2>&1
```

## Testing

Run the unit test suite:

```bash
./tests/run_tests.sh
```

Tests include:
- Loading `.env` files
- Sensitive data warnings
- DNS record fetching with mocked API

## Security

- Store credentials in a `.env` file with restrictive permissions:
  ```bash
  chmod 600 .env
  ```
- Do not commit `.env` files to version control
- Use token-based authentication when possible (`-t/--token`)
- At verbosity level 4 or above, sensitive values are printed—use cautiously in production

## Troubleshooting

### "Failed to login to Technitium API"
- Verify server URL is correct and accessible
- Check username and password
- Ensure API is enabled on Technitium server

### "No public IP address found"
- Check internet connectivity
- Verify one or both of `--no-ipv4` / `--no-ipv6` are not set
- Try with `--verbose 5` to see which public IP services are contacted

### "Record not found" or no update occurs
- Verify domain name and zone name are correct
- Use `--dryrun` to see what the script detects
- Check Technitium permissions for the logged-in user

## License

MIT

## Contributing

Contributions are welcome! Please run tests before submitting pull requests.

```bash
./tests/run_tests.sh
bash -n update-technitium-ip.sh
```
