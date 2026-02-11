# DynDNS
![Bash](https://img.shields.io/badge/language-bash-green) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A lightweight Dynamic DNS solution for BIND9 that automatically updates DNS records when your home IP address changes.

Perfect for self-hosted servers behind dynamic IP connections. The system consists of a client script that detects IP changes and a server script that applies updates to BIND9 zone files.

```
┌─────────────────┐         ┌─────────────────┐
│  Home Client    │  rsync  │   DNS Server    │
│  (dyndns.sh)    │ ──────► │ (dyndnsupdate)  │
│                 │   SSH   │                 │
│ Fetches IP      │         │ Updates BIND9   │
└─────────────────┘         └─────────────────┘
```

1. **Client** (`dyndns.sh`): Runs on your home machine, fetches your external IP, and syncs it to the DNS server
2. **Server** (`dyndnsupdate.sh`): Runs on your DNS server, reads the IP file, updates the zone, and reloads BIND9

## Features

- Automatic external IP detection from public services
- Change detection that only updates when your IP actually changes
- IP format validation before applying changes
- Optional backups before modifying zone files
- Comprehensive error checking and logging
- Secure file transfer via SSH/rsync

## Requirements

### Client Machine

- `curl` for fetching external IP
- `rsync` for secure file transfer
- SSH key authentication configured for passwordless access to the server

### DNS Server

- BIND9 installed and configured
- `rndc` utility configured
- Proper permissions to modify zone files

## Installation

### Client Setup

1. Clone this repository:

   ```bash
   git clone https://github.com/Avicennasis/dyndns.git
   cd dyndns
   ```

2. Edit `dyndns.sh` and configure:

   ```bash
   REMOTE_USER="your_username"
   REMOTE_HOST="your.dns.server"
   REMOTE_PATH="/etc/bind/zones"
   ```

3. Set up SSH key authentication:

   ```bash
   ssh-keygen -t ed25519
   ssh-copy-id your_username@your.dns.server
   ```

4. Make the script executable:

   ```bash
   chmod +x dyndns.sh
   ```

### Server Setup

1. Copy files to your DNS server:

   ```bash
   cp dyndnsupdate.sh /usr/local/bin/
   cp HOME.example /etc/bind/zones/
   ```

2. Edit `dyndnsupdate.sh` and configure:

   ```bash
   ZONES_DIR="/etc/bind/zones"
   ZONE_FILE="db.yourdomain.com"
   ```

3. Edit `HOME.example` to match your domain configuration

4. Make the script executable:

   ```bash
   chmod +x /usr/local/bin/dyndnsupdate.sh
   ```

## Usage

Once installed, both scripts are intended to run on a schedule via cron (see Scheduling below).

### Zone Template

The `HOME.example` file is a BIND9 zone template. Replace:

- `HOST.COM` with your actual domain
- `SERVERIP` with your server's static IP
- `HOMEREPLACEME` is automatically replaced with your dynamic home IP

### File Structure

```
dyndns/
├── dyndns.sh          # Client script (runs at home)
├── dyndnsupdate.sh    # Server script (runs on DNS server)
├── HOME.example       # Zone file template
├── LICENSE            # MIT License
└── README.md          # This file
```

## Scheduling

### Crontab

Add cron entries on both the client and server machines.

**Client machine:**

```bash
crontab -e
# Add: */5 * * * * /path/to/dyndns.sh >> /var/log/dyndns.log 2>&1
```

**Server machine:**

```bash
crontab -e
# Add: */5 * * * * /usr/local/bin/dyndnsupdate.sh >> /var/log/dyndnsupdate.log 2>&1
```

> **Note:** Always use absolute paths in crontab entries.

## Credits

**Author:** Léon "Avic" Simmons — [GitHub](https://github.com/Avicennasis)
