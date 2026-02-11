# Grab
![Bash](https://img.shields.io/badge/language-bash-green) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A modern, robust, and polite shell script wrapper for `wget` designed to download files from web directory listings and thread pages (e.g., 4chan).

## Features

- Validates inputs, handles errors strictly, and uses safe filename encoding
- Respects `robots.txt` by default with rate limiting, random delays, and a configurable User-Agent
- Supports recursive downloads, file filtering (include/exclude), and custom output directories
- Cross-platform: works on Linux, macOS, and Windows (via WSL/Git Bash)
- Automatically sets `--no-parent` to prevent ascending the directory tree
- Default recursion depth is limited as a guardrail

## Usage

```bash
./grab.sh [OPTIONS] <URL> [OUTPUT_DIR]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-r`, `--recursive` | Enable recursive retrieval | Off |
| `-l`, `--max-depth N` | Set recursion maximum depth level | `1` (if `-r` is set) |
| `-A`, `--include PATTERN` | Comma-separated list of file extensions/patterns to accept (e.g., `jpg,png`) | - |
| `-R`, `--exclude PATTERN` | Comma-separated list of file extensions/patterns to reject | - |
| `--dry-run` | Show what would be done without downloading | - |
| `-c`, `--continue` | Resume partially downloaded files | - |
| `--overwrite` | Overwrite existing files | Skip if exists |
| `--rate-limit RATE` | Limit download rate (e.g., `200k`, `1m`) | - |
| `--delay SECONDS` | Wait SECONDS between retrievals | `1` |
| `--timeout SECONDS` | Network timeout in seconds | `10` |
| `-U`, `--user-agent STR` | Set User-Agent string | - |
| `-H`, `--span-hosts` | Enable spanning across hosts (needed for some CDNs) | Off |
| `--ignore-robots` | Ignore robots.txt (not recommended) | Off |
| `-h`, `--help` | Show help message | - |

### Examples

**Basic directory download:**

Download all files from a directory listing to a local folder (defaults to `./domain/path`).

```bash
./grab.sh https://example.com/files/
```

**Download images from a thread (e.g., 4chan):**

Use `-H` to span hosts (needed for image CDNs), `-r -l 1` to grab linked files, and `-A` to filter for images.

```bash
./grab.sh -r -l 1 -H -A jpg,png,webm https://boards.4chan.org/wg/thread/12345
```

**Polite scraping:**

Limit rate to 200KB/s and wait 2 seconds between requests.

```bash
./grab.sh --rate-limit 200k --delay 2 https://example.com/archive/
```

**Dry run:**

See what would be downloaded without actually doing it.

```bash
./grab.sh --dry-run https://example.com/
```

> **Note:** Use `--ignore-robots` only if you have explicit permission from the site owner.

## Credits

**Author:** Léon "Avic" Simmons — [GitHub](https://github.com/Avicennasis)
