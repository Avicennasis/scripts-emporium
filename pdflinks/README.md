# pdflinks
![Bash](https://img.shields.io/badge/language-bash-green) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A modern command-line tool to extract PDF links from webpages.

## Features

- Extract PDF links from any webpage
- Optional download of all found PDFs
- Colored output for better readability
- Handles relative URLs automatically
- Saves links to a text file
- Fast -- uses curl for efficient fetching

## Requirements

The following standard Unix utilities are required (pre-installed on most systems):

- `curl` -- for fetching webpages
- `grep` -- for pattern matching
- `sed` -- for text processing
- `bash` 4.0+

## Installation

```bash
# Clone the repository
git clone https://github.com/Avicennasis/pdflinks.git

# Make the script executable
chmod +x pdflinks/pdflinks.sh

# Optionally, add to your PATH
sudo ln -s $(pwd)/pdflinks/pdflinks.sh /usr/local/bin/pdflinks
```

## Usage

```bash
# Basic usage - extract PDF links from a webpage
./pdflinks.sh https://example.com/documents

# Save links to a custom file
./pdflinks.sh -o my_links.txt https://example.com/papers

# Extract and download all PDFs
./pdflinks.sh --download https://example.com/reports

# Download to a specific directory
./pdflinks.sh -d -D ./my_pdfs https://example.com/files

# Quiet mode (only show links and errors)
./pdflinks.sh -q https://example.com/docs
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-h`, `--help` | Show help message and exit | - |
| `-v`, `--version` | Show version information | - |
| `-d`, `--download` | Download all found PDF files | Off |
| `-o`, `--output FILE` | Save links to FILE | `pdflinks.txt` |
| `-D`, `--dir DIR` | Download directory | `pdf_downloads` |
| `-q`, `--quiet` | Suppress informational output | Off |

### Examples

**Example output:**

```
[INFO] Fetching PDF links from: https://example.com/documents
[OK] Found 5 PDF link(s)

PDF Links:
----------------------------------------
https://example.com/documents/report-2026.pdf
https://example.com/documents/whitepaper.pdf
https://example.com/documents/guide.pdf
https://example.com/documents/manual.pdf
https://example.com/documents/specs.pdf
----------------------------------------

[INFO] Links saved to: pdflinks.txt
[OK] Done!
```

**Version history:**

- v2.0.0 (2026) -- Complete rewrite by Leon "Avic" Simmons. Replaced lynx with curl, added colored output and progress indicators, added download functionality with `--download` flag, added help system and version info, improved error handling and URL validation, extensive code documentation.
- v1.0.0 (2013) -- Original version by [Glutanimate](http://askubuntu.com/users/81372/).

## Credits

**Author:** Leon "Avic" Simmons -- [GitHub](https://github.com/Avicennasis)
