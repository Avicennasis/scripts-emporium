#!/bin/bash
#
# grab - A modern, polite, and robust web downloader wrapper for wget.
#
# Usage: grab [OPTIONS] <URL> [OUTPUT_DIR]
#
# See 'grab --help' for full usage.

set -euo pipefail

# --- Configuration & Defaults ---
VERSION="2.0.0"
DEFAULT_USER_AGENT="Mozilla/5.0 (compatible; GrabScript/${VERSION}; +https://github.com/example/grab)"
DEFAULT_DELAY="1"       # Seconds between requests
DEFAULT_RETRIES="3"
DEFAULT_TIMEOUT="10"    # Seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <URL> [OUTPUT_DIR]

A robust wrapper around wget for downloading files from directory listings and pages.

Arguments:
  URL                   The target URL to download from.
  OUTPUT_DIR            Directory to save files (default: ./<domain>/<path>).

Options:
  -r, --recursive       Enable recursive retrieval (default: OFF).
  -l, --max-depth N     Set recursion maximum depth level (default: 1 if -r is set).
  -A, --include PATTERN Comma-separated list of file extensions or patterns to accept (e.g. jpg,png).
  -R, --exclude PATTERN Comma-separated list of file extensions or patterns to reject.
  --dry-run             Show what would be done without downloading.
  -c, --continue        Resume partially downloaded files.
  --overwrite           Overwrite existing files (default: skip if exists).
  --rate-limit RATE     Limit download rate (e.g. 200k, 1m).
  --delay SECONDS       Wait SECONDS between retrievals (default: ${DEFAULT_DELAY}).
  --timeout SECONDS     Network timeout in seconds (default: ${DEFAULT_TIMEOUT}).
  -U, --user-agent STR  Set User-Agent string.
  -H, --span-hosts      Enable spanning across hosts (needed for some CDNs).
  --ignore-robots       Ignore robots.txt (NOT RECOMMENDED).
  -h, --help            Show this help message.
  -v, --version         Show version.

Examples:
  grab https://example.com/files/
  grab -r --include pdf https://example.com/docs/
  grab -r -H --include jpg,png https://boards.4chan.org/wg/thread/12345

EOF
}

# --- Argument Parsing ---

# Initialize variables
URL=""
OUTPUT_DIR=""
RECURSIVE=0
MAX_DEPTH=""
INCLUDE_PATTERN=""
EXCLUDE_PATTERN=""
DRY_RUN=0
CONTINUE=0
OVERWRITE=0
RATE_LIMIT=""
DELAY="${DEFAULT_DELAY}"
TIMEOUT="${DEFAULT_TIMEOUT}"
USER_AGENT="${DEFAULT_USER_AGENT}"
SPAN_HOSTS=0
ROBOTS=1

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -v|--version) echo "grab version ${VERSION}"; exit 0 ;;
        -r|--recursive) RECURSIVE=1; shift ;;
        -l|--max-depth) MAX_DEPTH="$2"; shift 2 ;;
        -A|--include) INCLUDE_PATTERN="$2"; shift 2 ;;
        -R|--exclude) EXCLUDE_PATTERN="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -c|--continue) CONTINUE=1; shift ;;
        --overwrite) OVERWRITE=1; shift ;;
        --rate-limit) RATE_LIMIT="$2"; shift 2 ;;
        --delay) DELAY="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        -U|--user-agent) USER_AGENT="$2"; shift 2 ;;
        -H|--span-hosts) SPAN_HOSTS=1; shift ;;
        --ignore-robots) ROBOTS=0; shift ;;
        -*) log_error "Unknown option: $1"; show_help; exit 1 ;;
        *) 
            if [[ -z "$URL" ]]; then
                URL="$1"
            elif [[ -z "$OUTPUT_DIR" ]]; then
                OUTPUT_DIR="$1"
            else
                log_error "Too many arguments provided."
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# --- Validation ---

if [[ -z "$URL" ]]; then
    log_error "URL is required."
    show_help
    exit 1
fi

# Basic URL validation (scheme)
if [[ ! "$URL" =~ ^https?:// ]]; then
    log_error "Invalid URL scheme. Must start with http:// or https://"
    exit 1
fi

# Check for wget
if ! command -v wget &> /dev/null; then
    log_error "wget is required but not installed. Please install wget."
    exit 1
fi

# --- Construct wget Command ---

WGET_CMD=("wget")

# 1. Base Options
WGET_CMD+=("--no-verbose") # Less noise, but still shows progress
WGET_CMD+=("--show-progress")
WGET_CMD+=("--restrict-file-names=windows") # Safe filenames
WGET_CMD+=("--user-agent=${USER_AGENT}")
WGET_CMD+=("--timeout=${TIMEOUT}")
WGET_CMD+=("--tries=${DEFAULT_RETRIES}")
WGET_CMD+=("--random-wait") # Politeness
WGET_CMD+=("--wait=${DELAY}")

# 2. Recursion & Depth
if [[ "$RECURSIVE" -eq 1 ]]; then
    WGET_CMD+=("--recursive")
    WGET_CMD+=("--no-parent") # Safety: Don't go up
    if [[ -n "$MAX_DEPTH" ]]; then
        WGET_CMD+=("--level=${MAX_DEPTH}")
    fi
else
    # If not recursive, we might still want page requisites if it's a page
    # But standard 'grab file' behavior implies just the file.
    # If user wants a single page's images, they usually need -r -l 1
    :
fi

# 3. Filtering
if [[ -n "$INCLUDE_PATTERN" ]]; then
    WGET_CMD+=("--accept=${INCLUDE_PATTERN}")
fi
if [[ -n "$EXCLUDE_PATTERN" ]]; then
    WGET_CMD+=("--reject=${EXCLUDE_PATTERN}")
fi

# 4. Output & Overwriting
if [[ "$OVERWRITE" -eq 0 ]]; then
    WGET_CMD+=("--no-clobber") # Skip existing files
fi

if [[ "$CONTINUE" -eq 1 ]]; then
    WGET_CMD+=("--continue")
fi

if [[ -n "$OUTPUT_DIR" ]]; then
    # Create output dir if it doesn't exist
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_info "Creating output directory: $OUTPUT_DIR"
        if [[ "$DRY_RUN" -eq 0 ]]; then
            mkdir -p "$OUTPUT_DIR"
        fi
    fi
    WGET_CMD+=("--directory-prefix=${OUTPUT_DIR}")
else
    # Default behavior: wget creates host/path structure.
    # We'll let wget handle it unless we want to flatten it.
    # To keep it simple and safe, we let wget default or user specifies.
    :
fi

# 5. Politeness & Safety
if [[ "$ROBOTS" -eq 0 ]]; then
    WGET_CMD+=("--execute" "robots=off")
fi

if [[ -n "$RATE_LIMIT" ]]; then
    WGET_CMD+=("--limit-rate=${RATE_LIMIT}")
fi

if [[ "$SPAN_HOSTS" -eq 1 ]]; then
    WGET_CMD+=("--span-hosts")
else
    # Default: strict same domain
    :
fi

# 6. Dry Run
if [[ "$DRY_RUN" -eq 1 ]]; then
    WGET_CMD+=("--spider")
    log_info "Dry run enabled. No files will be downloaded."
fi

# --- Execution ---

log_info "Target: $URL"
log_info "Command: ${WGET_CMD[*]} \"$URL\""

if [[ "$DRY_RUN" -eq 1 ]]; then
    # Just print the command again clearly
    echo "${WGET_CMD[@]} \"$URL\""
else
    # Execute
    "${WGET_CMD[@]}" "$URL"
    EXIT_CODE=$?
    
    if [[ $EXIT_CODE -eq 0 ]]; then
        log_success "Download completed successfully."
    else
        log_warn "Download finished with exit code $EXIT_CODE. Check output for details."
    fi
fi
