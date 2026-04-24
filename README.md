# Avic's Scripts Emporium

[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/Avicennasis/scripts-emporium/badge)](https://scorecard.dev/viewer/?uri=github.com/Avicennasis/scripts-emporium)
[![Release](https://img.shields.io/github/v/release/Avicennasis/scripts-emporium?display_name=tag)](https://github.com/Avicennasis/scripts-emporium/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

A collection of standalone utility scripts for sysadmin tasks, web scraping, DNS management, and everyday automation. Each script lives in its own folder with its own README.

## Scripts

| Script | Language | Description |
|--------|----------|-------------|
| [acronymize](acronymize/) | Bash | Generates playful acronym expansions by mapping input letters to random dictionary words |
| [backup](backup/) | Bash | Creates archival and incremental backups using rsync and unison with logging and email notifications |
| [cl-keyword-scrape](cl-keyword-scrape/) | Bash | Scrapes Craigslist listings matching a regex pattern with HTML output and email alerts |
| [craigslist-search](craigslist-search/) | Python | Watches Craigslist search results for new posts containing configured keywords and sends email alerts |
| [domx-records](domx-records/) | Python | Manages email-related DNS posture (SPF/DMARC/MX) across DigitalOcean-hosted domains |
| [downornot](downornot/) | Bash | Monitors website uptime continuously and sends HTML email alerts when sites go down |
| [dyndns](dyndns/) | Bash | Automatically updates BIND9 DNS records when your home IP address changes via SSH/rsync |
| [find-dupes](find-dupes/) | Bash | Finds duplicate files recursively using SHA256 hashing and generates a CSV report |
| [grab](grab/) | Bash | Polite wget wrapper for downloading files from web directory listings with rate limiting |
| [janitor](janitor/) | Bash | Automates cleanup of old files in a directory with detailed logging and optional email reports |
| [link-audit](link-audit/) | Python | Scans and validates URLs with an interactive HTML dashboard for filtering and managing results |
| [pdflinks](pdflinks/) | Bash | Extracts PDF links from webpages and optionally downloads them |
| [restartnotice](restartnotice/) | Bash | Sends HTML email notifications with system details whenever a server reboots |
| [trafficcam](trafficcam/) | Bash | Downloads traffic camera snapshots at intervals and emails them |
| [weather](weather/) | Bash | Generates spoken weather reports using the National Weather Service API with optional TTS |

## Usage

Each script folder contains its own README with detailed usage instructions, configuration options, and examples. Click through to any script above to get started.

Most scripts are self-contained with no external dependencies beyond standard Unix tools. Where dependencies exist (e.g., Python packages, `rsync`, `unison`), they are documented in the script's README.

## License

MIT License. See [LICENSE](LICENSE) for details.
