# Find Dupes
![Bash](https://img.shields.io/badge/language-bash-green) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A simple, robust shell script for Cygwin on Windows 10 to recursively scan directories, calculate SHA256 hashes, and identify duplicate files.

## Features

- Recursive traversal of all subdirectories
- Secure SHA256 hashing to identify duplicates
- CSV report generation (`duplicates_report.csv`) containing hash, file path, and size of all duplicates found
- Handles filenames with spaces and special characters correctly

## Requirements

- **Cygwin** installed on your Windows machine
- Standard tools available in Cygwin:
  - `bash`
  - `find`
  - `sha256sum`
  - `sort`
  - `uniq`
  - `awk`
  - `cut`
  - `du`

## Installation

1. Clone this repository or download `find_dupes.sh`.

2. Make the script executable:

   ```bash
   chmod +x find_dupes.sh
   ```

## Usage

```bash
./find_dupes.sh [OPTIONS] [DIRECTORY]
```

If `DIRECTORY` is not specified, the current directory is scanned.

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-h`, `--help` | Show help message and exit | - |
| `-v`, `--verbose` | Enable verbose output (shows progress and details) | Off |
| `-o`, `--output FILE` | Specify output file | `duplicates_report.csv` |

### Examples

**Scan the current directory:**

```bash
./find_dupes.sh
```

**Scan a specific folder with verbose output:**

```bash
./find_dupes.sh -v /cygdrive/c/Users/MyUser/Documents
```

**Save report to a custom file:**

```bash
./find_dupes.sh -o my_report.csv
```

### Output Format

The script creates a CSV file in the current working directory.

```csv
Hash,FilePath,Size
<sha256_hash>,"<path_to_file_1>",<size>
<sha256_hash>,"<path_to_file_2>",<size>
...
```

## Credits

**Author:** Léon "Avic" Simmons — [GitHub](https://github.com/Avicennasis)
