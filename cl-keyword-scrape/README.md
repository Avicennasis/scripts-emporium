# Craigslist Keyword Scraper
![Bash](https://img.shields.io/badge/language-bash-green) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A maintainable Bash CLI that searches a Craigslist section, fetches listings, and prints only the posts that match a user-supplied regex, extracting the listing title and body text, highlighting matched keywords, and writing organized results to an output file.

## Features

- Pure Bash implementation (no embedded Python parsing)
- Configurable search parameters (city, section, pages, offsets, sort, query)
- Configurable match regex (case-insensitive) with deduplicated hit reporting
- Multiple output formats (`plain`, `tsv`, `block`)
- Email notifications with HTML formatting (optional plain text): send on success, failure, or both; digest email per run or per individual hit
- Robust HTML parsing via an auto-detected backend: `htmlq` (preferred), `pup`, or `hxnormalize` + `hxselect` (`html-xml-utils`) with `lynx` fallback
- Network resiliency: retries, timeouts, redirects
- Rate limiting: configurable delay between requests
- Safe temp handling and cleanup via traps
- `--print-urls` mode to validate URL extraction without fetching posts
- Easy scheduling with systemd or crontab

## Requirements

### Runtime

- Bash (4+ recommended)
- `curl`
- Common utilities: `getopt`, `awk`, `sed`, `grep`, `sort`, `mktemp`, `wc`, `tee`

### HTML parsing (one required)

Choose one of the following:

1. **htmlq** (recommended):

   ```bash
   sudo snap install htmlq
   ```

2. **html-xml-utils** + lynx (good fallback, available via APT):

   ```bash
   sudo apt update
   sudo apt install -y html-xml-utils lynx
   ```

3. **pup**: install via your preferred method (package manager or releases). Project: [https://github.com/ericchiang/pup](https://github.com/ericchiang/pup)

### Email notifications (optional)

- `sendmail` or `mail` command

```bash
# Ubuntu/Debian
sudo apt install mailutils

# RHEL/CentOS
sudo yum install mailx
```

## Installation

1. Download and make the script executable:

   ```bash
   curl -LO https://example.com/cl-keyword-scrape.sh
   chmod +x cl-keyword-scrape.sh
   ```

2. Install dependencies (see Requirements).

3. Verify:

   ```bash
   ./cl-keyword-scrape.sh --help
   ```

## Usage

```bash
./cl-keyword-scrape.sh [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--city NAME` | Craigslist city subdomain | `pittsburgh` |
| `--section NAME` | Section path | `gms` |
| `--pages N` | Number of pages to fetch | `2` |
| `--start N` | Offset start for pagination | `0` |
| `--step N` | Offset step for pagination | `100` |
| `--sort VALUE` | Sort order | `date` |
| `--query TEXT` | Craigslist query parameter | (empty) |
| `--regex REGEX` | Extended regex used for matches | built-in list |
| `--output FILE` | Output file path | `results.txt` |
| `--append` | Append to output file instead of overwriting | off |
| `--format plain\|tsv\|block` | Output formatting | `block` |
| `--delay SECONDS` | Delay between HTTP requests | `2` |
| `--timeout SECONDS` | HTTP request timeout | `20` |
| `--retries N` | Number of retries on failure | `3` |
| `--parser auto\|htmlq\|pup\|hx` | Force a specific HTML parser backend | `auto` |
| `--print-urls` | Only print unique listing URLs (does not fetch posts) | off |
| `--verbose` | Verbose logs to stderr | off |
| `--email-to EMAIL` | Send results to this email address | -- |
| `--email-from EMAIL` | From address | current user@hostname |
| `--email-when never\|success\|failure\|both` | When to send emails | `never` |
| `--email-per run\|hit` | One email digest per run or one per match | `run` |
| `--html-off` | Send plain text emails instead of HTML | off |

### Examples

Default behavior (two pages of Pittsburgh garage sales):

```bash
./cl-keyword-scrape.sh
```

Match a simple keyword:

```bash
./cl-keyword-scrape.sh --pages 1 --regex 'sale'
```

Use a Craigslist query and a separate match regex:

```bash
./cl-keyword-scrape.sh --query "guitar" --regex 'fender|gibson|martin'
```

Print URLs only (debug URL extraction):

```bash
./cl-keyword-scrape.sh --verbose --print-urls | head
```

TSV output for downstream processing:

```bash
./cl-keyword-scrape.sh --format tsv --output results.tsv
```

Human-friendly multi-line "block" output:

```bash
./cl-keyword-scrape.sh --format block --output results.txt
```

Be more conservative with rate limiting:

```bash
./cl-keyword-scrape.sh --delay 3 --timeout 30 --retries 2
```

Send email notifications on success:

```bash
./cl-keyword-scrape.sh --email-to you@example.com --email-when success
```

Send email on both success and failure with plain text:

```bash
./cl-keyword-scrape.sh --email-to you@example.com --email-when both --html-off
```

Get an email for every single match:

```bash
./cl-keyword-scrape.sh --email-to you@example.com --email-when success --email-per hit
```

## Configuration

### Output formats

**plain** -- one line per match:

```
Match! (Sale)(PS4) https://... - Listing Title
```

**tsv** -- tab-delimited:

```
Match!    (Sale)(PS4)    https://...    Listing Title
```

**block** -- multi-line record per match:

```
Match! (Sale)(PS4)
URL:   https://...
Title: Listing Title
```

### How it works

1. Builds Craigslist search URLs using `--city`, `--section`, pagination offsets, and optional `--query`.
2. Fetches each search page with `curl`.
3. Extracts all anchor `href` values and filters them to listing URLs for the selected section.
4. Fetches each listing page and extracts:
   - Title (`#titletextonly`)
   - Body text (`#postingbody`)
5. Runs a case-insensitive regex match and prints only matched listings.
6. Writes output to the file specified by `--output`.

## Scheduling

### systemd

systemd timers are more reliable and easier to debug than cron jobs. They provide better logging and do not depend on the cron daemon.

#### Create a systemd service file

Create `/etc/systemd/system/cl-scraper.service`:

```ini
[Unit]
Description=Craigslist Keyword Scraper
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=YOUR_USERNAME
WorkingDirectory=/home/YOUR_USERNAME
ExecStart=/path/to/cl-keyword-scrape.sh --city pittsburgh --section gms --pages 3 --regex 'your|keywords|here' --output /home/YOUR_USERNAME/results.txt --email-to you@example.com --email-when both
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

> **Note:** Replace `YOUR_USERNAME` and adjust the paths and parameters.

#### Create a systemd timer file

Create `/etc/systemd/system/cl-scraper.timer`:

```ini
[Unit]
Description=Run Craigslist Scraper every 6 hours
Requires=cl-scraper.service

[Timer]
# Run every 6 hours
OnCalendar=*-*-* 00,06,12,18:00:00
# If the system was off, run on next boot
Persistent=true
# Add a random delay of 0-10 minutes to avoid exact timing
RandomizedDelaySec=600

[Install]
WantedBy=timers.target
```

#### Enable and start the timer

```bash
sudo systemctl daemon-reload
sudo systemctl enable cl-scraper.timer
sudo systemctl start cl-scraper.timer
```

#### Verify the timer is active

```bash
# Check timer status
sudo systemctl status cl-scraper.timer

# List all timers
sudo systemctl list-timers --all

# View service logs
sudo journalctl -u cl-scraper.service -f
```

### Crontab

If you prefer crontab or do not have systemd access:

#### Edit your crontab

```bash
crontab -e
```

#### Add a cron job

Run every 6 hours at :15 past the hour:

```cron
15 */6 * * * /path/to/cl-keyword-scrape.sh --city pittsburgh --section gms --pages 3 --regex 'your|keywords|here' --output /home/USERNAME/results.txt --email-to you@example.com --email-when both >> /home/USERNAME/scraper.log 2>&1
```

Run daily at 8 AM:

```cron
0 8 * * * /path/to/cl-keyword-scrape.sh --city pittsburgh --section gms --pages 5 --output /home/USERNAME/results.txt --email-to you@example.com --email-when success >> /home/USERNAME/scraper.log 2>&1
```

Run every Monday at 9 AM:

```cron
0 9 * * 1 /path/to/cl-keyword-scrape.sh --city pittsburgh --section gms --output /home/USERNAME/results.txt --email-to you@example.com --email-when both >> /home/USERNAME/scraper.log 2>&1
```

#### Verify cron job is scheduled

```bash
crontab -l
```

## Troubleshooting

### "Missing dependency" errors

Install the missing tool(s) listed. For HTML parsing, you must have at least one backend available: `htmlq` or `pup` or `hxselect` + `hxnormalize` (and `lynx` for the `hx` backend).

### No listing URLs found

Run:

```bash
./cl-keyword-scrape.sh --verbose --print-urls
```

If it prints `Unique listing URLs: 0`, Craigslist markup may have changed again, or your section/city may be incorrect. Try forcing a different parser backend:

```bash
./cl-keyword-scrape.sh --parser htmlq --verbose --print-urls
./cl-keyword-scrape.sh --parser hx --verbose --print-urls
```

### Empty results even though you expect matches

Confirm your regex:

```bash
./cl-keyword-scrape.sh --pages 1 --regex 'sale' --verbose
```

Use `--format block` to review what title text is being extracted.

### Requests failing or timing out

Increase timeouts and delay, reduce retries if needed:

```bash
./cl-keyword-scrape.sh --timeout 45 --delay 3 --retries 2 --verbose
```

### Email notifications not working

Install mail utilities:

```bash
sudo apt install mailutils  # Ubuntu/Debian
sudo yum install mailx      # RHEL/CentOS
```

Test email manually:

```bash
echo "Test message" | mail -s "Test Subject" you@example.com
```

Check if sendmail or mail command is available:

```bash
which sendmail
which mail
```

Verify email settings:

- Confirm `--email-to` is a valid email address.
- Check that `--email-when` is not set to `never`.
- Use `--verbose` to see email-related log messages.

For systemd scheduled jobs, check logs:

```bash
sudo journalctl -u cl-scraper.service | grep -i email
```

### systemd troubleshooting

Timer not running:

```bash
sudo systemctl is-enabled cl-scraper.timer
sudo systemctl cat cl-scraper.timer
sudo systemctl show cl-scraper.timer
```

Service failing:

```bash
sudo journalctl -u cl-scraper.service -n 50
sudo journalctl -u cl-scraper.service -b
sudo systemctl start cl-scraper.service
sudo systemctl status cl-scraper.service
```

Permission issues:

- Ensure the `User=` directive in the service file matches your username.
- Verify the script is executable: `chmod +x /path/to/cl-keyword-scrape.sh`
- Check that the output directory exists and is writable by that user.

Network not ready:

- The `After=network-online.target` and `Wants=network-online.target` directives ensure network is ready.
- If still having issues, add a delay: `ExecStartPre=/bin/sleep 10`

### Crontab troubleshooting

Cron job not running:

```bash
sudo systemctl status cron   # Ubuntu/Debian
sudo systemctl status crond  # RHEL/CentOS
grep CRON /var/log/syslog    # Ubuntu/Debian
sudo journalctl -u cron      # Systems with systemd
crontab -l
```

Path issues: cron runs with a minimal environment; use absolute paths for everything. Set PATH at the top of your crontab:

```cron
PATH=/usr/local/bin:/usr/bin:/bin
```

Command not found errors: find the full path with `which curl` or `which htmlq` and add to PATH in crontab or use absolute paths in the script.

Script not executing: ensure script is executable (`chmod +x`), test the exact command from crontab manually, and check permissions and ownership.

No output or logs: always redirect output to a log file (`>> /path/to/logfile.log 2>&1`), check that the log directory exists and is writable, and view the log with `tail -f /home/USERNAME/scraper.log`.

Email not working in cron: install mail utilities, check local mail with `mail` or `cat /var/mail/$USER`, and configure cron to use MAILTO by adding `MAILTO=you@example.com` at the top of crontab.

Timezone confusion: cron uses system timezone. Check with `timedatectl` or `date`, and set timezone if needed with `sudo timedatectl set-timezone America/New_York`.

## Credits

**Author:** Leon "Avic" Simmons -- [GitHub](https://github.com/Avicennasis)
