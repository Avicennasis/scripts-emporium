# Craigslist Keyword Watcher
![Python](https://img.shields.io/badge/language-python-blue) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A small script that watches Craigslist search results for new posts and sends an alert when a post body contains any of your configured keywords.

This version runs on Python 3, scrapes Craigslist HTML search results (not RSS), sends mail via local `sendmail` / `ssmtp` (no SMTP credentials in the script), and avoids duplicate alerts with a seen-state JSON file. It prints a clear summary so it does not exit silently.

## Features

- Search Craigslist by region + category (+ optional query)
- Parse multiple Craigslist result layouts (new + older)
- Fetch each post and scan `<section id="postingbody">`
- Match keywords case-insensitively
- Send alerts using your machine's mail setup (e.g. `ssmtp` sendmail emulation)
- Deduplicate across runs via `seen_craigslist.json`
- Pagination, throttling, loop/polling mode, dry-run mode
- Optional mail debug output
- Carrier email-to-SMS gateway support for SMS alerts

## Requirements

- Python 3.10+ recommended
- A configured local mailer providing `sendmail` or `ssmtp` (on many hosts, `sendmail` is a symlink to `/usr/sbin/ssmtp`)
- `requests`
- `beautifulsoup4`

```bash
python3 -m pip install --user requests beautifulsoup4
```

## Installation

1. Clone the repository and confirm the mailer exists:

   ```bash
   command -v sendmail
   readlink -f "$(command -v sendmail)"
   ```

   On Ubuntu with sSMTP, this often shows `/usr/sbin/ssmtp`.

2. Make the script executable:

   ```bash
   chmod +x craigslist_watch.py
   ```

## Usage

```bash
python3 craigslist_watch.py --region boston --category gms --keywords "mario,ps5,nintendo"
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--region` | Craigslist subdomain (e.g. `boston`, `newyork`, `sfbay`) | `boston` |
| `--category` | Craigslist category path (e.g. `gms`, `sss`) | `gms` |
| `--query` | Optional search query string | (none) |
| `--keywords` | Comma-separated keywords to match | built-in list |
| `--seen-file` | JSON file for dedupe state | `seen_craigslist.json` |
| `--pages` | How many search pages to scan | `1` |
| `--page-size` | Offset step for pagination (`s=`) | `120` |
| `--sleep` | Seconds to sleep between HTTP requests | `1.5` |
| `--loop` | If >0, rerun every N seconds | `0` |
| `--dry-run` | Print matches; do not send email | off |

### Examples

Run with a Craigslist search query:

```bash
python3 craigslist_watch.py --region boston --category gms --query "garage sale" --keywords "nintendo,gameboy"
```

Scan multiple search pages (pagination):

```bash
python3 craigslist_watch.py --region boston --category gms --pages 2 --keywords "xbox,ps5"
```

Loop/poll every 5 minutes:

```bash
python3 craigslist_watch.py --region boston --category gms --keywords "mario,ps5" --loop 300
```

Dry-run (prints matches, sends nothing):

```bash
python3 craigslist_watch.py --region boston --category gms --keywords "mario,ps5" --dry-run
```

Throttle requests more gently (reduces chance of blocks):

```bash
python3 craigslist_watch.py --region boston --category gms --sleep 3.0 --keywords "mario,ps5"
```

## Configuration

### Environment variables

| Variable | Description | Required |
|----------|-------------|----------|
| `ALERT_TO` | Destination email or email-to-SMS gateway | Yes |
| `ALERT_FROM` | From header address | No |
| `MAIL_DEBUG` | Set to `1` to run mailer verbose and print output | No |

```bash
export ALERT_TO="you@gmail.com"
export ALERT_FROM="you@gmail.com"
```

### Carrier email-to-SMS gateways

You can send to an email-to-SMS gateway address as `ALERT_TO`. Reliability varies by carrier and region.

| Carrier | Gateway format |
|---------|---------------|
| AT&T | `number@txt.att.net` or `number@mms.att.net` |
| Verizon | `number@vtext.com` |
| T-Mobile | `number@tmomail.net` |

```bash
export ALERT_TO="6175551212@vtext.com"
```

### Output behavior

The script always prints a summary at the end of a run:

- No new posts: `No new posts to scan ... nothing to send.`
- New posts but no matches: `Scanned X new posts ... no keyword matches; nothing to send via email.`
- Matches found: prints `[alert] match 'keyword' -> URL` per match and a final summary.

### Seen state

The file `seen_craigslist.json` stores listing IDs already processed, preventing duplicate alerts across runs. To start fresh (re-alert on old listings):

```bash
rm -f seen_craigslist.json
```

## Troubleshooting

### "It runs but I get no email"

Most common cause: no keyword matches. Try a very common keyword like `sale` or run with dry-run:

```bash
python3 craigslist_watch.py --region boston --category gms --keywords "sale" --dry-run
```

### Verify mail handoff works from the script

Enable verbose mail debug output:

```bash
export MAIL_DEBUG=1
python3 craigslist_watch.py --region boston --category gms --keywords "sale"
```

This prints the mailer command, return code, and verbose output from `ssmtp/sendmail` so you can confirm delivery.

### Craigslist block page

If you get an error like "Craigslist returned a blocked page", your host/IP/network is getting filtered. Things that help:

- Increase `--sleep` (e.g. 3-5 seconds)
- Scan fewer pages (`--pages 1`)
- Do not run too frequently (`--loop 600` instead of 60)
- Ensure a realistic User-Agent (script sets one by default)

### Where are mail logs on Ubuntu 24.04?

If you are using `ssmtp` sendmail emulation, there is typically no queue and log entries vary. The fastest check is `MAIL_DEBUG=1`.

If you have a full MTA (Postfix/Exim), logs are usually:

- `/var/log/mail.log`
- `journalctl -u postfix`

> **Note:** Be a decent internet citizen: do not hammer Craigslist. Use throttling (`--sleep`) and reasonable polling intervals (`--loop`).

## Credits

**Author:** Leon "Avic" Simmons -- [GitHub](https://github.com/Avicennasis)
