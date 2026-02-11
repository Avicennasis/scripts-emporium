# DigitalOcean DNS Mail Lockdown + Audit Tools
![Python](https://img.shields.io/badge/language-python-blue) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A small set of scripts for managing email-related DNS posture across many domains hosted on DigitalOcean DNS.

These tools are designed for two common scenarios:

1. **Most domains should never send or receive email** -- you want to prevent spoofing and disable inbound mail by enforcing SPF `v=spf1 -all`, DMARC `p=reject` with strict alignment, MX dead-end target (`mail.invalid.`), and removal of DKIM and (optionally) wildcard DNS records.

2. **A small subset of domains legitimately process mail** -- you want to audit all domains and quickly identify outliers and misconfigurations.

## Features

- Bulk "no-mail" hardening for domains that should never send or receive email (`lockdown_mail.py`)
- Per-domain detailed audit with record dumps and text reports (`do_dns_audit.py`)
- Grouped audit that clusters domains with identical posture for quick outlier detection (`do_dns_audit_grouped.py`)
- Dry-run mode on all scripts to preview changes before applying
- Flexible authentication: `.env` file, environment variable, or command-line token
- Allowlist support for domains that legitimately process mail
- JSON and NDJSON summary output options
- Per-domain record dump in JSON format

## Requirements

- Python 3.9+ recommended (3.8 may work)
- DigitalOcean DNS (scripts use the DigitalOcean Domains API and assume your DNS zones are managed in DigitalOcean)
- `requests`

```bash
python3 -m pip install requests
```

## Installation

Clone the repository and configure authentication (see Configuration below).

## Usage

This project contains three scripts:

- `lockdown_mail.py` -- bulk hardening for domains that should never send or receive email
- `do_dns_audit.py` -- per-domain detailed audit
- `do_dns_audit_grouped.py` -- grouped audit (cluster domains with identical posture)

### lockdown_mail.py

For each domain you provide, this script:

1. Deletes DKIM records (TXT and CNAME records whose `name` contains `_domainkey`)
2. Sets DMARC to enforce rejection at `_dmarc` with strict alignment (`adkim=s`, `aspf=s`)
3. Sets SPF to authorize nobody (`v=spf1 -all` at `@`, targeting only TXT records beginning with `v=spf1` to avoid clobbering unrelated verification TXT records)
4. Replaces MX records with a dead-end (`MX @ -> mail.invalid.`, priority 0)
5. Optionally deletes wildcard records (any record whose `name` begins with `*`)
6. Optionally adds DMARC report receiver authorization in a separate zone

#### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--domains-file PATH` | File containing domains to lock down (required) | -- |
| `--token TOKEN` | DigitalOcean API token | `DO_TOKEN` env var |
| `--dry-run` | Print intended API calls without making changes | off |
| `--dmarc-report-domain DOMAIN` | Domain that receives DMARC aggregate reports (rua) | -- |
| `--dmarc-localpart-prefix PREFIX` | Prefix for plus-tagged DMARC mailbox local-part | `DMARC` |
| `--report-auth-zone ZONE` | Upsert `<domain>._report._dmarc` TXT `v=DMARC1` into this zone | -- |
| `--deadend-mx-target HOST` | MX target used to disable inbound mail | `mail.invalid.` |
| `--delete-wildcards` | Delete wildcard records (`*`) | off |
| `--continue-on-error` | Continue processing remaining domains if one fails | off |

#### Examples

Dry-run first (recommended):

```bash
python3 lockdown_mail.py --domains-file domains.txt --dry-run
```

Apply changes:

```bash
python3 lockdown_mail.py --domains-file domains.txt
```

Send DMARC reports to a separate domain and add report authorization records:

```bash
python3 lockdown_mail.py \
  --domains-file domains.txt \
  --dmarc-report-domain dmarc-reports.example \
  --dmarc-localpart-prefix DMARC \
  --report-auth-zone dmarc-reports.example
```

Delete wildcard records too:

```bash
python3 lockdown_mail.py --domains-file domains.txt --delete-wildcards
```

### do_dns_audit.py

A detailed, per-domain audit that lists every domain, fetches all DNS records, writes a JSON dump of each domain's records, prints a per-domain summary to stdout, and writes a consolidated human-friendly text report.

It checks:

- Root MX records and posture: `dead` if root MX targets are all `--dead-mx-host`, `active` if MX exists and is not dead-end, `none` if no MX exists
- Root SPF TXT records (TXT at `@` beginning with `v=spf1`)
- DMARC TXT (`_dmarc`)
- DKIM-ish record count (`_domainkey` in TXT/CNAME names)
- Wildcard record count (`*`)

#### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--token TOKEN` | DigitalOcean token | `DO_TOKEN` env var |
| `--outdir DIR` | Where record dump JSON files are written | `/tmp/do_dns_audit_<timestamp>/` |
| `--report-file PATH` | Where to write the text report | `/tmp/do_dns_audit_report_<timestamp>.txt` |
| `--mail-domains-file PATH` | Allowlist of domains expected to process mail | -- |
| `--dead-mx-host HOST` | Hostname treated as the "dead mail" MX target | `mail.invalid` |
| `--dump-json` | Also write `summary.json` and `summary.ndjson` to `--outdir` | off |

#### Examples

Run an audit (outputs default to `/tmp`):

```bash
python3 do_dns_audit.py
```

Audit and flag unexpected/incorrect mail posture:

```bash
python3 do_dns_audit.py --mail-domains-file mail_domains.txt
```

Specify report output:

```bash
python3 do_dns_audit.py --report-file ./dns_audit_report.txt
```

### do_dns_audit_grouped.py

A grouped audit that clusters domains by an "email posture signature" so you can instantly see the large group of domains that match your standard and small groups of outliers (e.g. mail-processing domains or misconfigured domains).

By default it prints a grouped summary to stdout (with truncated domain lists) and writes a full grouped TXT report (with every domain listed) to `/tmp`. Optional JSON outputs and record dumps are opt-in.

#### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--token TOKEN` | DigitalOcean token | `DO_TOKEN` env var |
| `--mail-domains-file PATH` | Allowlist of domains expected to process mail | -- |
| `--dead-mx-host HOST` | Hostname treated as the "dead mail" MX target | `mail.invalid` |
| `--show-all` | Print all domains per group to stdout (no truncation) | off |
| `--show-domains-per-group N` | How many domains to show per group in stdout | -- |
| `--report-file PATH` | Where to write the grouped TXT report | `/tmp/do_dns_audit_grouped_report_<timestamp>.txt` |
| `--dump-records` | Write `<domain>.records.json` for each domain to `--outdir` | off |
| `--dump-json` | Write `summary.json`, `summary.ndjson`, and `groups.json` to `--outdir` | off |
| `--outdir DIR` | Where JSON outputs go | `/tmp/do_dns_audit_grouped_<timestamp>/` |

#### Examples

Grouped audit:

```bash
python3 do_dns_audit_grouped.py
```

Show every domain under each group in stdout:

```bash
python3 do_dns_audit_grouped.py --show-all
```

Use allowlist for mail-processing domains:

```bash
python3 do_dns_audit_grouped.py --mail-domains-file mail_domains.txt
```

Dump JSON summaries and per-domain records:

```bash
python3 do_dns_audit_grouped.py --dump-json --dump-records --outdir ./audit_out
```

## Configuration

### Authentication

All scripts check for authentication credentials in this order:

1. **`.env` file (recommended)** -- most secure for local development
2. **Environment variable** -- good for CI/CD and containers
3. **Command-line `--token`** -- convenient for one-off runs, but visible in shell history

#### Option 1: .env file (recommended)

Create a `.env` file in the project directory:

```bash
echo 'DO_TOKEN="dop_v1_your_token_here"' > .env
chmod 600 .env
```

> **Note:** Always set restrictive permissions on your `.env` file. The token is not visible in shell history or process listings (`ps aux`), and the file is automatically excluded from git via `.gitignore`.

Verify permissions:

```bash
ls -la .env
# Should show: -rw-------
```

#### Option 2: Environment variable

```bash
export DO_TOKEN="dop_v1_..."
```

Add to your shell profile (`~/.bashrc`, `~/.zshrc`) for persistence:

```bash
echo 'export DO_TOKEN="dop_v1_..."' >> ~/.bashrc
source ~/.bashrc
```

#### Option 3: Command-line argument

```bash
python3 do_dns_audit.py --token "dop_v1_..."
```

> **Note:** Command-line arguments are visible in `ps aux` output and shell history. Avoid this method for production use.

### Domains file format

A plain text file, one domain per line:

```txt
# domains.txt
example.com
example.net
example.org
```

Blank lines are ignored. Lines starting with `#` are comments.

### Allowlist file format (--mail-domains-file)

A plain text file, one domain per line:

```txt
# mail_domains.txt
mail-primary.example
support.example
example.com
```

Blank lines are ignored. Lines starting with `#` are comments.

## Troubleshooting

### "I'm getting 401 Unauthorized"

Cause: missing/invalid DigitalOcean token, or token lacks permissions.

- If using `.env` file, verify it exists and has the correct format:

  ```bash
  cat .env
  # Should show: DO_TOKEN="dop_v1_..."
  ```

- If using environment variable, confirm you exported the token:

  ```bash
  echo "$DO_TOKEN"
  ```

- Verify your token has the correct permissions in the DigitalOcean dashboard.
- Create a new token in DigitalOcean with appropriate permissions if needed.

### "Token not being read from .env file"

Cause: `.env` file format issues or wrong location.

- Ensure the `.env` file is in the same directory where you run the script.
- Verify the format is correct (no extra spaces around `=`):

  ```bash
  # Correct formats:
  DO_TOKEN="dop_v1_abc123..."
  DO_TOKEN=dop_v1_abc123...
  DO_TOKEN='dop_v1_abc123...'
  ```

- Check file permissions allow reading:

  ```bash
  ls -la .env
  chmod 600 .env  # Fix if needed
  ```

### "MX record creation fails / Data needs to end with a dot (.)"

DigitalOcean requires MX targets to be a fully-qualified domain name ending in `.`. Use `mail.invalid.` (with trailing dot) as the MX target. `lockdown_mail.py` already enforces the trailing dot automatically.

### "TXT records look quoted / my values don't match"

DNS dashboards often display quotes around TXT values, but different systems store them differently. The scripts normalize TXT values by stripping wrapping quotes for comparisons. Prefer storing values without quotes in DNS UIs.

### "DMARC reports aren't arriving at my report inbox"

Some receivers require that the destination domain explicitly authorize report receipt. Use `lockdown_mail.py` with `--report-auth-zone <DMARC_REPORT_DOMAIN>` to publish:

```
<DOMAIN>._report._dmarc.<DMARC_REPORT_DOMAIN> TXT "v=DMARC1"
```

Ensure your `rua=` address points to an inbox that exists and can receive mail.

### "A few domains really DO send/receive mail. How do I avoid breaking them?"

Do not include those domains in `lockdown_mail.py` input. Use the audit scripts with `--mail-domains-file` to verify posture: allowlisted domains should be `active`, and non-allowlisted domains should be `dead` or `none` (depending on your standard).

### "The scripts are writing files but I can't find them"

By default, outputs are written under `/tmp` with timestamped names. Look in `/tmp`:

```bash
ls -la /tmp | grep do_dns_audit
```

Or set explicit paths with `--outdir` and `--report-file`.

## Credits

**Author:** Leon "Avic" Simmons -- [GitHub](https://github.com/Avicennasis)
