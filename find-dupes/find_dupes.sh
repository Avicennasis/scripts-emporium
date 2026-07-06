#!/bin/bash

# Default values
SEARCH_DIR="."
OUTPUT_FILE="duplicates_report.csv"
VERBOSE=false
FORCE=false

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS] [DIRECTORY]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message and exit"
    echo "  -v, --verbose        Enable verbose output"
    echo "  -o, --output FILE    Specify output file (default: duplicates_report.csv)"
    echo "  -f, --force          Overwrite existing output file without prompting"
    echo ""
    echo "Arguments:"
    echo "  DIRECTORY            Directory to scan (default: current directory)"
    echo ""
    echo "When stdin is not a terminal (cron, CI, pipes), an existing output"
    echo "file is overwritten automatically instead of prompting."
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift
            shift
            ;;
        *)
            SEARCH_DIR="$1"
            shift
            ;;
    esac
done

# Check if directory exists
if [ ! -d "$SEARCH_DIR" ]; then
    echo "Error: Directory '$SEARCH_DIR' does not exist."
    exit 1
fi

# Check if output file exists.
# Only prompt when running interactively; --force or a non-TTY stdin
# (cron, CI, pipes) overwrites without prompting so automated runs
# never hang waiting for input.
if [ -f "$OUTPUT_FILE" ] && [ "$FORCE" != true ] && [ ! -t 0 ]; then
    echo "Output file '$OUTPUT_FILE' exists; overwriting (non-interactive mode)."
elif [ -f "$OUTPUT_FILE" ] && [ "$FORCE" != true ]; then
    echo "Output file '$OUTPUT_FILE' already exists."
    while true; do
        read -p "Do you want to [O]verwrite, [R]ename, or [C]ancel? " choice
        case $choice in
            [Oo]* ) break;;
            [Rr]* ) 
                read -p "Enter new filename: " new_name
                OUTPUT_FILE="$new_name"
                if [ -f "$OUTPUT_FILE" ]; then
                     echo "File '$OUTPUT_FILE' also exists."
                     continue
                fi
                break;;
            [Cc]* ) exit 0;;
            * ) echo "Please answer O, R, or C.";;
        esac
    done
fi

echo "Scanning '$SEARCH_DIR' for duplicates..."
if [ "$VERBOSE" = true ]; then
    echo "Output file: $OUTPUT_FILE"
    echo "Verbose mode enabled."
fi

echo "Calculating SHA256 hashes (this may take a while)..."

# Create a temporary file for raw hashes; clean it up on any exit
# (normal completion, error, or Ctrl+C) so interrupted runs don't
# accumulate temp files in /tmp.
TMP_HASHES=$(mktemp)
trap 'rm -f "$TMP_HASHES"' EXIT

# Find all files, calculate sha256sum, and save to temp file
if [ "$VERBOSE" = true ]; then
    # In verbose mode, we can't easily show progress of find|xargs without slowing it down,
    # but we can at least say we are starting.
    echo "Running: find \"$SEARCH_DIR\" -type f -print0 | xargs -0 sha256sum"
fi

find "$SEARCH_DIR" -type f -print0 | xargs -0 sha256sum > "$TMP_HASHES"

echo "Processing duplicates..."

# Create/Overwrite output CSV with header
echo "Hash,FilePath,Size" > "$OUTPUT_FILE"

# Logic to find duplicates:
sort "$TMP_HASHES" | uniq -w 64 -D | while read -r line; do
    hash=$(echo "$line" | awk '{print $1}')
    file=$(echo "$line" | cut -c 67-)
    
    if [ "$VERBOSE" = true ]; then
        echo "Found duplicate: $file"
    fi

    # Calculate human-readable file size
    size=$(du -h "$file" | awk '{print $1}')
    
    # Escape double quotes in filename for CSV
    file="${file//\"/\"\"}"
    
    # Append to CSV
    echo "$hash,\"$file\",$size" >> "$OUTPUT_FILE"
done

echo "Done! Report saved to '$OUTPUT_FILE'"
echo "Found $(wc -l < "$OUTPUT_FILE" | awk '{print $1 - 1}') duplicate files."
