# Link Audit Tool
![Python](https://img.shields.io/badge/language-python-blue) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A fast, configurable URL scanner that generates interactive HTML reports, perfect for auditing bookmark collections, validating link lists, or monitoring website availability.

## Features

- Batch processing -- scans up to 25 URLs concurrently (configurable)
- Smart interleaving -- distributes requests across domains to avoid rate limiting
- Fast timeouts -- 3-second connection timeout to quickly skip dead servers
- Persistent deletion -- remove links from reports (changes saved to JSON)
- Interactive filtering -- real-time column filters for Website, URL, Status, Description
- Sortable columns -- click headers to sort ascending/descending
- Recheck mode -- re-scan existing reports without the original input file

## Requirements

- Python 3.7+
- `requests` library
- `beautifulsoup4` library

```bash
pip install requests beautifulsoup4
```

## Usage

```bash
# 1. Create a text file with URLs (one per line)
echo "https://example.com" > links.txt

# 2. Run the scanner
python audit_links.py --input links.txt

# 3. Start the web server
python server.py

# 4. Open http://localhost:8000 in your browser
```

### Scanner Options (`audit_links.py`)

```bash
python audit_links.py --help  # Show all options
```

| Option | Description | Default |
|--------|-------------|---------|
| `--help`, `-h` | Show help message and exit | - |
| `--input`, `-i` | Input file containing URLs | `Links1.txt` |
| `--output`, `-o` | Output JSON data file | `report_data.json` |
| `--batch-size`, `-b` | Concurrent requests | `25` |
| `--timeout`, `-t` | Request timeout (seconds) | `10` |
| `--user-agent`, `-u` | HTTP User-Agent string | Chrome 120 |
| `--verbose`, `-v` | Enable debug logging | Off |
| `--recheck`, `-r` | Re-scan URLs from existing JSON | Off |

### Scanner Examples

```bash
# Scan with custom settings
python audit_links.py -i mybookmarks.txt -o mybookmarks.json -b 50

# Re-check all links in an existing report
python audit_links.py --recheck -o report_data.json

# Verbose mode for debugging
python audit_links.py -v
```

### Server Options (`server.py`)

```bash
python server.py --help  # Show all options
```

| Option | Description | Default |
|--------|-------------|---------|
| `--help`, `-h` | Show help message and exit | - |
| `--port`, `-p` | Server port | `8000` |
| `--data-file`, `-d` | JSON file to serve | `report_data.json` |
| `--verbose`, `-v` | Log all requests | Off |

### Server Examples

```bash
# Run on a different port
python server.py --port 9000

# Serve a specific data file
python server.py --data-file mybookmarks.json
```

### Report Features

**Status Indicators:**

- OK (green) -- 2xx success responses
- Forbidden (yellow) -- 403 status
- Not Found (red) -- 404 status
- Error (red) -- connection failures, DNS errors, timeouts

**Filtering:**

Type in the filter boxes to search:

- `youtube` in Website -- show only YouTube links
- `forbidden` in Status -- show 403 responses
- `redirect` in Status -- show links with redirects
- `tutorial` in Description -- search titles and descriptions

**Actions:**

- Click column headers to sort
- Click "Remove" to permanently delete a link from the report
- All links open in new tabs

### File Structure

```
linkscan/
├── audit_links.py    # URL scanner script
├── server.py         # Local web server
├── index.html        # Report viewer UI
├── report_data.json  # Generated scan results (not tracked)
└── Links1.txt        # Your URL list (not tracked)
```

## Credits

**Author:** Leon "Avic" Simmons -- [GitHub](https://github.com/Avicennasis)
