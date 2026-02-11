#!/bin/bash
# ==============================================================================
# pdflinks - PDF Link Extractor
# ==============================================================================
#
# NAME:         pdflinks
# VERSION:      2.0.0
# AUTHOR:       Léon "Avic" Simmons (originally by Glutanimate, 2013)
# LICENSE:      MIT License
# REPOSITORY:   https://github.com/Avicennasis/pdflinks
#
# DESCRIPTION:  Extracts PDF links from any webpage and optionally downloads
#               them. Uses curl to fetch page content and grep/sed to parse
#               links ending in .pdf (case-insensitive).
#
# DEPENDENCIES: curl, grep, sed (standard on most Unix systems)
#
# USAGE:        pdflinks [OPTIONS] <URL>
#               pdflinks --help
#
# ==============================================================================

# ------------------------------------------------------------------------------
# Bash Strict Mode
# ------------------------------------------------------------------------------
# -e: Exit immediately if a command exits with a non-zero status
# -u: Treat unset variables as an error
# -o pipefail: Return value of a pipeline is the status of the last command
#              to exit with a non-zero status, or zero if all succeed
set -euo pipefail

# ------------------------------------------------------------------------------
# Script Metadata
# ------------------------------------------------------------------------------
readonly VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_OUTPUT_FILE="pdflinks.txt"
readonly DEFAULT_DOWNLOAD_DIR="pdf_downloads"

# ------------------------------------------------------------------------------
# Color Definitions (ANSI escape codes for terminal output)
# ------------------------------------------------------------------------------
# These make the output more readable and user-friendly
readonly RED='\033[0;31m'      # Error messages
readonly GREEN='\033[0;32m'    # Success messages
readonly YELLOW='\033[0;33m'   # Warnings
readonly BLUE='\033[0;34m'     # Info/progress messages
readonly CYAN='\033[0;36m'     # Highlights (URLs, counts)
readonly BOLD='\033[1m'        # Bold text
readonly NC='\033[0m'          # No Color (reset)

# ------------------------------------------------------------------------------
# Utility Functions
# ------------------------------------------------------------------------------

# Print an informational message (blue prefix)
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Print a success message (green prefix)
success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# Print a warning message (yellow prefix)
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Print an error message to stderr (red prefix)
error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Print a fatal error and exit with code 1
die() {
    error "$1"
    exit 1
}

# ------------------------------------------------------------------------------
# Help and Version Display
# ------------------------------------------------------------------------------

# Display usage information
show_help() {
    cat << EOF
${BOLD}${SCRIPT_NAME}${NC} - Extract PDF links from webpages

${BOLD}USAGE:${NC}
    ${SCRIPT_NAME} [OPTIONS] <URL>

${BOLD}OPTIONS:${NC}
    -h, --help          Show this help message and exit
    -v, --version       Show version information and exit
    -d, --download      Download all found PDF files
    -o, --output FILE   Save links to FILE (default: ${DEFAULT_OUTPUT_FILE})
    -D, --dir DIR       Download directory (default: ${DEFAULT_DOWNLOAD_DIR})
    -q, --quiet         Suppress informational output (errors still shown)

${BOLD}EXAMPLES:${NC}
    # Extract PDF links from a webpage
    ${SCRIPT_NAME} https://example.com/documents

    # Extract and save to custom file
    ${SCRIPT_NAME} -o my_links.txt https://example.com/papers

    # Extract and download all PDFs
    ${SCRIPT_NAME} --download https://example.com/reports

    # Download to a specific directory
    ${SCRIPT_NAME} -d -D ./my_pdfs https://example.com/files

${BOLD}OUTPUT:${NC}
    Found PDF links are printed to stdout and saved to a text file.
    When downloading, files are saved to the specified directory.

${BOLD}LICENSE:${NC}
    MIT License - see LICENSE file for details

EOF
}

# Display version information
show_version() {
    echo "${SCRIPT_NAME} version ${VERSION}"
    echo "Originally by Glutanimate (2013), modernized 2026"
}

# ------------------------------------------------------------------------------
# Dependency Checking
# ------------------------------------------------------------------------------

# Verify that all required commands are available on the system
check_dependencies() {
    local missing_deps=()
    
    # Check each required command
    for cmd in curl grep sed; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # If any dependencies are missing, report and exit
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        die "Missing required dependencies: ${missing_deps[*]}
Please install them and try again."
    fi
}

# ------------------------------------------------------------------------------
# URL Validation
# ------------------------------------------------------------------------------

# Basic validation to ensure the URL looks reasonable
validate_url() {
    local url="$1"
    
    # Check if URL starts with http:// or https://
    if [[ ! "$url" =~ ^https?:// ]]; then
        # Try to be helpful - maybe they forgot the protocol
        warn "URL doesn't start with http:// or https://"
        info "Attempting with https://${url}"
        echo "https://${url}"
        return
    fi
    
    echo "$url"
}

# ------------------------------------------------------------------------------
# Core Functionality: Extract PDF Links
# ------------------------------------------------------------------------------

# Fetch a webpage and extract all links pointing to PDF files
# Arguments:
#   $1 - The URL to fetch
# Returns:
#   Prints PDF URLs to stdout, one per line
extract_pdf_links() {
    local url="$1"
    
    # Use curl to fetch the webpage content
    # -s: Silent mode (no progress bar)
    # -L: Follow redirects
    # -A: Set user agent (some sites block curl's default)
    # --connect-timeout: Don't wait forever for connection
    # --max-time: Maximum time for the whole operation
    local page_content
    page_content=$(curl -sL \
        -A "Mozilla/5.0 (compatible; pdflinks/${VERSION})" \
        --connect-timeout 10 \
        --max-time 60 \
        "$url" 2>/dev/null) || {
        die "Failed to fetch URL: $url
Please check the URL is correct and accessible."
    }
    
    # Extract PDF links using grep and sed
    # This regex pattern looks for:
    # 1. href="..." or href='...' attributes containing .pdf
    # 2. Handles both absolute and relative URLs
    # The -i flag makes it case-insensitive (catches .PDF, .Pdf, etc.)
    echo "$page_content" | \
        grep -oEi 'href=["\x27][^"\x27]*\.pdf["\x27]' | \
        sed -E "s/href=[\"']([^\"']*)[\"']/\1/i" | \
        sort -u  # Remove duplicates and sort
}

# Convert relative URLs to absolute URLs
# Arguments:
#   $1 - Base URL (the page we fetched)
#   $2 - Link URL (possibly relative)
# Returns:
#   Prints the absolute URL
make_absolute_url() {
    local base_url="$1"
    local link="$2"
    
    # If already absolute, return as-is
    if [[ "$link" =~ ^https?:// ]]; then
        echo "$link"
        return
    fi
    
    # Extract base components from the URL
    local protocol="${base_url%%://*}://"
    local domain
    domain=$(echo "$base_url" | sed -E 's|^https?://([^/]+).*|\1|')
    
    # Handle different relative URL formats
    if [[ "$link" =~ ^// ]]; then
        # Protocol-relative URL (//example.com/file.pdf)
        echo "${protocol#://}${link}"
    elif [[ "$link" =~ ^/ ]]; then
        # Root-relative URL (/path/to/file.pdf)
        echo "${protocol}${domain}${link}"
    else
        # Path-relative URL (../file.pdf or file.pdf)
        local base_path
        base_path=$(echo "$base_url" | sed -E 's|^https?://[^/]+||; s|/[^/]*$|/|')
        echo "${protocol}${domain}${base_path}${link}"
    fi
}

# ------------------------------------------------------------------------------
# Download Functionality
# ------------------------------------------------------------------------------

# Download all PDF files from a list
# Arguments:
#   $1 - File containing URLs (one per line)
#   $2 - Destination directory
download_pdfs() {
    local url_file="$1"
    local dest_dir="$2"
    
    # Create destination directory if it doesn't exist
    mkdir -p "$dest_dir"
    
    local total
    total=$(wc -l < "$url_file")
    local count=0
    local failed=0
    
    info "Downloading ${total} PDF file(s) to ${CYAN}${dest_dir}${NC}"
    
    # Read each URL and download
    while IFS= read -r url; do
        ((count++)) || true
        
        # Extract filename from URL
        local filename
        filename=$(basename "$url" | sed 's/?.*//')  # Remove query strings
        
        # Handle duplicate filenames by adding a number
        local dest_path="${dest_dir}/${filename}"
        local counter=1
        while [[ -f "$dest_path" ]]; do
            local name_without_ext="${filename%.pdf}"
            dest_path="${dest_dir}/${name_without_ext}_${counter}.pdf"
            ((counter++))
        done
        
        # Download with progress indicator
        echo -ne "\r${BLUE}[${count}/${total}]${NC} Downloading: ${filename}..."
        
        if curl -sL -o "$dest_path" "$url" 2>/dev/null; then
            echo -e "\r${GREEN}[${count}/${total}]${NC} Downloaded: ${filename}    "
        else
            echo -e "\r${RED}[${count}/${total}]${NC} Failed: ${filename}    "
            ((failed++)) || true
            rm -f "$dest_path"  # Clean up partial download
        fi
    done < "$url_file"
    
    echo ""  # New line after progress
    
    # Summary
    local succeeded=$((total - failed))
    success "Downloaded ${succeeded}/${total} files to ${CYAN}${dest_dir}${NC}"
    
    if [[ $failed -gt 0 ]]; then
        warn "${failed} file(s) failed to download"
    fi
}

# ------------------------------------------------------------------------------
# Main Function
# ------------------------------------------------------------------------------

main() {
    # Default option values
    local do_download=false
    local output_file="$DEFAULT_OUTPUT_FILE"
    local download_dir="$DEFAULT_DOWNLOAD_DIR"
    local quiet=false
    local url=""
    
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -d|--download)
                do_download=true
                shift
                ;;
            -o|--output)
                # Ensure an argument follows -o
                if [[ -z "${2:-}" ]]; then
                    die "Option -o requires a filename argument"
                fi
                output_file="$2"
                shift 2
                ;;
            -D|--dir)
                # Ensure an argument follows -D
                if [[ -z "${2:-}" ]]; then
                    die "Option -D requires a directory argument"
                fi
                download_dir="$2"
                shift 2
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -*)
                die "Unknown option: $1
Use --help for usage information."
                ;;
            *)
                # Positional argument = URL
                if [[ -n "$url" ]]; then
                    die "Multiple URLs provided. Only one URL is supported.
Use --help for usage information."
                fi
                url="$1"
                shift
                ;;
        esac
    done
    
    # Validate that a URL was provided
    if [[ -z "$url" ]]; then
        error "No URL provided"
        echo ""
        show_help
        exit 1
    fi
    
    # Check dependencies before proceeding
    check_dependencies
    
    # Validate and possibly fix the URL
    url=$(validate_url "$url")
    
    # Inform user we're starting
    [[ "$quiet" == false ]] && info "Fetching PDF links from: ${CYAN}${url}${NC}"
    
    # Extract PDF links
    local pdf_links
    pdf_links=$(extract_pdf_links "$url")
    
    # Check if any PDFs were found
    if [[ -z "$pdf_links" ]]; then
        warn "No PDF links found on this page"
        exit 0
    fi
    
    # Convert relative URLs to absolute and store in temp file
    local temp_file
    temp_file=$(mktemp)
    trap "rm -f '$temp_file'" EXIT  # Clean up temp file on exit
    
    while IFS= read -r link; do
        make_absolute_url "$url" "$link" >> "$temp_file"
    done <<< "$pdf_links"
    
    # Count and display results
    local link_count
    link_count=$(wc -l < "$temp_file")
    
    [[ "$quiet" == false ]] && success "Found ${CYAN}${link_count}${NC} PDF link(s)"
    
    # Output to stdout
    echo ""
    echo -e "${BOLD}PDF Links:${NC}"
    echo "----------------------------------------"
    cat "$temp_file"
    echo "----------------------------------------"
    echo ""
    
    # Save to file
    cp "$temp_file" "$output_file"
    [[ "$quiet" == false ]] && info "Links saved to: ${CYAN}${output_file}${NC}"
    
    # Download if requested
    if [[ "$do_download" == true ]]; then
        echo ""
        download_pdfs "$temp_file" "$download_dir"
    fi
    
    [[ "$quiet" == false ]] && success "Done!"
}

# ------------------------------------------------------------------------------
# Script Entry Point
# ------------------------------------------------------------------------------
# Only run main if this script is being executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
