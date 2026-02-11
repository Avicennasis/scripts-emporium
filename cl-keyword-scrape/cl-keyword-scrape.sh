#!/usr/bin/env bash
# cl-keyword-scrape.sh
#
# Scrape Craigslist search results, fetch each posting, and print matches for a keyword regex.
#
# Parsing backend (auto-detected):
#   - htmlq (preferred): https://github.com/mgdm/htmlq
#   - pup:              https://github.com/ericchiang/pup
#   - hxselect stack:   hxnormalize + hxselect (package: html-xml-utils)
#
# Example:
#   ./cl-keyword-scrape.sh --city pittsburgh --section gms --pages 2 --step 100 \
#     --regex 'mario|ps[34]|xbox|gameboy|linux|sega|brewing|books|guitar' --output results.txt

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.2.0"

CITY="pittsburgh"
SECTION="gms"
PAGES=2
STEP=100
START=0
SORT="date"
QUERY=""
REGEX='mario|ps[34]|xbox|gameboy|linux|sega|brewing|books|guitar'
OUTPUT="results.txt"
APPEND=0
DELAY=2
TIMEOUT=20
RETRIES=3
USER_AGENT="cl-keyword-scrape/${VERSION} (curl)"
FORMAT="block"       # plain | tsv
PRINT_URLS_ONLY=0
VERBOSE=0
PARSER="auto"        # auto | htmlq | pup | hx

# Email notification settings
EMAIL_TO=""
EMAIL_FROM=""
EMAIL_WHEN="never"   # never | success | failure | both
EMAIL_PER="run"      # run | hit
HTML_EMAIL=1         # 1 for HTML, 0 for plain text

TMPDIR=""
MATCHES=()           # Array to store match results for digest
ERRORS=()            # Array to store errors for digest
TOTAL_MATCHES=0

usage() {
  cat <<'EOF'
Usage:
  cl-keyword-scrape.sh [options]

Options:
  --city NAME              Craigslist city subdomain (default: pittsburgh)
  --section NAME           Section path (default: gms)
  --pages N                Number of pages to fetch (default: 2)
  --start N                Starting offset (default: 0)
  --step N                 Offset step per page (default: 100)
  --sort VALUE             Sort order (default: date)
  --query TEXT             Craigslist query parameter (default: empty)
  --regex REGEX            Extended regex to match (default: mario|ps[34]|xbox|...)
  --output FILE            Output file (default: results.txt)
  --append                 Append to output file (default: overwrite)
  --format plain|tsv|block Output format (default: block)
  --print-urls             Only print the unique URLs found (do not fetch posts)
  --delay SECONDS          Delay between HTTP requests (default: 2)
  --timeout SECONDS        curl timeout (default: 20)
  --retries N              curl retries (default: 3)
  --user-agent STRING      User-Agent header (default: script name/version)
  --parser auto|htmlq|pup|hx  Parsing backend (default: auto)
  --verbose                Verbose logging to stderr
  --version                Print version
  -h, --help               Show help

Email notifications:
  --email-to EMAIL         Send results to this email address
  --email-from EMAIL       From address (default: current user@hostname)
  --email-when WHEN        When to send: never|success|failure|both (default: never)
  --email-per TYPE         Email per: run|hit (default: run)
  --html-off               Send plain text emails instead of HTML

Output formats:
  plain:  Match! (hit1)(hit2) URL - Title
  tsv:    Match! <TAB> (hit1)(hit2) <TAB> URL <TAB> Title
  block:  Multi-line format with URL and Title on separate lines

Exit codes:
  0 success, 1 usage/dependency error, 2 runtime/network error
EOF
}

log() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2
  fi
}

die_usage() {
  printf 'Error: %s\n' "$*" >&2
  usage >&2
  exit 1
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die_usage "Missing dependency: $1"
}

cleanup() {
  local rc=$?
  [[ -n "${TMPDIR:-}" && -d "${TMPDIR:-}" ]] && rm -rf "$TMPDIR"
  exit "$rc"
}

trap cleanup EXIT
trap 'printf "\nInterrupted.\n" >&2; exit 2' INT TERM

urlencode() {
  local s="${1:-}" out="" c hex i
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      ' ') out+='%20' ;;
      *) printf -v hex '%%%02X' "'$c"; out+="$hex" ;;
    esac
  done
  printf '%s' "$out"
}

fetch() {
  local url="$1"
  curl \
    --fail --silent --show-error --location \
    --max-time "$TIMEOUT" \
    --retry "$RETRIES" --retry-delay 1 --retry-all-errors \
    -H "User-Agent: ${USER_AGENT}" \
    "$url"
}

build_search_url() {
  local offset="$1"
  local base="https://${CITY}.craigslist.org/search/${SECTION}"
  local qs="s=${offset}&sort=$(urlencode "$SORT")"
  if [[ -n "$QUERY" ]]; then
    qs="${qs}&query=$(urlencode "$QUERY")"
  fi
  printf '%s?%s' "$base" "$qs"
}

abs_url() {
  local u="$1"
  if [[ "$u" =~ ^https?:// ]]; then
    printf '%s\n' "$u"
  elif [[ "$u" =~ ^/ ]]; then
    printf 'https://%s.craigslist.org%s\n' "$CITY" "$u"
  else
    printf 'https://%s.craigslist.org/%s\n' "$CITY" "$u"
  fi
}

select_parser() {
  case "$PARSER" in
    htmlq|pup|hx) ;;
    auto) ;;
    *) die_usage "Invalid --parser: $PARSER" ;;
  esac

  if [[ "$PARSER" == "auto" ]]; then
    if command -v htmlq >/dev/null 2>&1; then
      PARSER="htmlq"
    elif command -v pup >/dev/null 2>&1; then
      PARSER="pup"
    elif command -v hxselect >/dev/null 2>&1 && command -v hxnormalize >/dev/null 2>&1; then
      PARSER="hx"
    else
      die_usage "No HTML parser found. Install one of: htmlq, pup, or html-xml-utils (hxselect/hxnormalize)."
    fi
  else
    case "$PARSER" in
      htmlq) need_cmd htmlq ;;
      pup) need_cmd pup ;;
      hx) need_cmd hxselect; need_cmd hxnormalize; need_cmd lynx ;;
    esac
  fi

  log "Parser selected: $PARSER"
}

extract_listing_urls() {
  # Read HTML from stdin. Print one absolute listing URL per line.
  # Strategy: extract all <a href>, then filter to URLs that look like postings for the chosen section.
  # This is more resilient to Craigslist UI/class changes than relying on a specific class name.

  local pattern="/${SECTION}/(d/|[0-9]+\\.html)"

  case "$PARSER" in
    htmlq)
      htmlq --attribute href 'a' \
        | sed -e 's/[[:space:]]\+$//' -e '/^$/d' \
        | grep -E "$pattern" || true
      ;;
    pup)
      pup 'a attr{href}' \
        | sed -e 's/[[:space:]]\+$//' -e '/^$/d' \
        | grep -E "$pattern" || true
      ;;
    hx)
      hxnormalize -x \
        | hxselect -i -c -s $'\n' 'a::attr(href)' \
        | sed -e 's/[[:space:]]\+$//' -e '/^$/d' \
        | grep -E "$pattern" || true
      ;;
  esac \
  | while IFS= read -r u; do
      # Drop obviously bad/non-http links defensively
      [[ -n "$u" ]] || continue
      [[ "$u" =~ ^(javascript:|mailto:) ]] && continue
      abs_url "$u"
    done
}


extract_title() {
  # Read HTML from stdin. Print a single-line title.
  case "$PARSER" in
    htmlq)
      htmlq --text --ignore-whitespace 'span#titletextonly' \
        | head -n 1 \
        | tr -d '\r' \
        | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//'
      ;;
    pup)
      pup 'span#titletextonly text{}' \
        | head -n 1 \
        | tr -d '\r' \
        | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//'
      ;;
    hx)
      hxnormalize -x \
        | hxselect -i -c 'span#titletextonly' \
        | lynx -stdin -dump \
        | head -n 1 \
        | tr -d '\r' \
        | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//'
      ;;
  esac
}

extract_body_text() {
  # Read HTML from stdin. Print body text (multi-line).
  case "$PARSER" in
    htmlq)
      htmlq --text --ignore-whitespace '#postingbody' \
        | tr -d '\r' \
        | sed -e '/^$/d' -e '/^QR Code Link to This Post$/d'
      ;;
    pup)
      pup '#postingbody text{}' \
        | tr -d '\r' \
        | sed -e '/^$/d' -e '/^QR Code Link to This Post$/d'
      ;;
    hx)
      hxnormalize -x \
        | hxselect -i -c '#postingbody' \
        | lynx -stdin -dump \
        | tr -d '\r' \
        | sed -e '/^$/d' -e '/^QR Code Link to This Post$/d'
      ;;
  esac
}

collect_hits() {
  # Args: content_string
  # Output: (hit1)(hit2)... (unique, case-insensitive). Returns nonzero if no hits.
  local content="$1"
  local hits=() line
  while IFS= read -r line; do
    hits+=("$line")
  done < <(printf '%s\n' "$content" | LC_ALL=C grep -Eoi "$REGEX" | awk '
    { k=tolower($0); if (!seen[k]++) print $0 }
  ')

  [[ "${#hits[@]}" -gt 0 ]] || return 1

  local out="" h
  for h in "${hits[@]}"; do out+="(${h})"; done
  printf '%s' "$out"
}

track_match() {
  # Store match for digest email
  local hits="$1" url="$2" title="$3"
  MATCHES+=("$hits|$url|$title")
  ((TOTAL_MATCHES++))
}

track_error() {
  # Store error for digest email
  local error="$1"
  ERRORS+=("$error")
}

generate_html_email() {
  local subject="$1"
  local match_count="${#MATCHES[@]}"
  local error_count="${#ERRORS[@]}"

  cat <<EOF
Subject: ${subject}
From: ${EMAIL_FROM}
To: ${EMAIL_TO}
MIME-Version: 1.0
Content-Type: text/html; charset=UTF-8

<!DOCTYPE html>
<html>
<head>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      max-width: 900px;
      margin: 0 auto;
      padding: 20px;
      background-color: #f5f5f5;
    }
    .container {
      background-color: #ffffff;
      border-radius: 8px;
      padding: 30px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    h1 {
      color: #2c3e50;
      border-bottom: 3px solid #3498db;
      padding-bottom: 10px;
      margin-top: 0;
    }
    h2 {
      color: #34495e;
      margin-top: 30px;
      border-left: 4px solid #3498db;
      padding-left: 10px;
    }
    .summary {
      background-color: #ecf0f1;
      padding: 15px;
      border-radius: 5px;
      margin: 20px 0;
    }
    .summary p {
      margin: 5px 0;
    }
    .success { color: #27ae60; font-weight: bold; }
    .error { color: #e74c3c; font-weight: bold; }
    .warning { color: #f39c12; font-weight: bold; }
    table {
      width: 100%;
      border-collapse: collapse;
      margin: 20px 0;
      background-color: #fff;
    }
    th {
      background-color: #3498db;
      color: white;
      padding: 12px;
      text-align: left;
      font-weight: 600;
    }
    td {
      padding: 12px;
      border-bottom: 1px solid #ecf0f1;
    }
    tr:hover {
      background-color: #f8f9fa;
    }
    .keywords {
      color: #e74c3c;
      font-weight: bold;
    }
    a {
      color: #3498db;
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
    .error-box {
      background-color: #fadbd8;
      border-left: 4px solid #e74c3c;
      padding: 10px;
      margin: 10px 0;
      border-radius: 3px;
    }
    .footer {
      margin-top: 30px;
      padding-top: 20px;
      border-top: 1px solid #ecf0f1;
      color: #7f8c8d;
      font-size: 0.9em;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>🔍 Craigslist Keyword Scraper Results</h1>

    <div class="summary">
      <p><strong>City:</strong> ${CITY}</p>
      <p><strong>Section:</strong> ${SECTION}</p>
      <p><strong>Pages Scraped:</strong> ${PAGES}</p>
      <p><strong>Search Regex:</strong> <code>${REGEX}</code></p>
      <p><strong>Total Matches:</strong> <span class="success">${match_count}</span></p>
EOF

  if [[ "$error_count" -gt 0 ]]; then
    echo "      <p><strong>Errors:</strong> <span class=\"error\">${error_count}</span></p>"
  fi

  cat <<EOF
    </div>
EOF

  if [[ "$match_count" -gt 0 ]]; then
    cat <<EOF

    <h2>📋 Matches Found</h2>
    <table>
      <thead>
        <tr>
          <th>Keywords</th>
          <th>Title</th>
          <th>URL</th>
        </tr>
      </thead>
      <tbody>
EOF

    local i match hits url title
    for match in "${MATCHES[@]}"; do
      IFS='|' read -r hits url title <<< "$match"
      cat <<EOF
        <tr>
          <td class="keywords">${hits}</td>
          <td>${title}</td>
          <td><a href="${url}" target="_blank">View Listing</a></td>
        </tr>
EOF
    done

    cat <<EOF
      </tbody>
    </table>
EOF
  fi

  if [[ "$error_count" -gt 0 ]]; then
    cat <<EOF

    <h2>⚠️ Errors Encountered</h2>
EOF
    for error in "${ERRORS[@]}"; do
      echo "    <div class=\"error-box\">${error}</div>"
    done
  fi

  cat <<EOF

    <div class="footer">
      <p>Generated by cl-keyword-scrape.sh v${VERSION}</p>
      <p>Run completed at $(date +'%Y-%m-%d %H:%M:%S')</p>
    </div>
  </div>
</body>
</html>
EOF
}

generate_plain_email() {
  local subject="$1"
  local match_count="${#MATCHES[@]}"
  local error_count="${#ERRORS[@]}"

  cat <<EOF
Subject: ${subject}
From: ${EMAIL_FROM}
To: ${EMAIL_TO}

Craigslist Keyword Scraper Results
=====================================

Summary:
--------
City:           ${CITY}
Section:        ${SECTION}
Pages Scraped:  ${PAGES}
Search Regex:   ${REGEX}
Total Matches:  ${match_count}
EOF

  if [[ "$error_count" -gt 0 ]]; then
    echo "Errors:         ${error_count}"
  fi

  echo ""

  if [[ "$match_count" -gt 0 ]]; then
    echo "Matches Found:"
    echo "-------------"
    echo ""

    local match hits url title
    for match in "${MATCHES[@]}"; do
      IFS='|' read -r hits url title <<< "$match"
      echo "Keywords: ${hits}"
      echo "Title:    ${title}"
      echo "URL:      ${url}"
      echo ""
    done
  fi

  if [[ "$error_count" -gt 0 ]]; then
    echo "Errors Encountered:"
    echo "------------------"
    echo ""
    for error in "${ERRORS[@]}"; do
      echo "- ${error}"
    done
    echo ""
  fi

  cat <<EOF
---
Generated by cl-keyword-scrape.sh v${VERSION}
Run completed at $(date +'%Y-%m-%d %H:%M:%S')
EOF
}

send_email() {
  local subject="$1"
  local is_success="$2"  # 1 for success, 0 for failure

  # Check if we should send based on EMAIL_WHEN setting
  case "$EMAIL_WHEN" in
    never)
      return 0
      ;;
    success)
      [[ "$is_success" -eq 1 ]] || return 0
      ;;
    failure)
      [[ "$is_success" -eq 0 ]] || return 0
      ;;
    both)
      # Always send
      ;;
  esac

  log "Sending email to ${EMAIL_TO}"

  local email_body
  if [[ "$HTML_EMAIL" -eq 1 ]]; then
    email_body="$(generate_html_email "$subject")"
  else
    email_body="$(generate_plain_email "$subject")"
  fi

  # Try to send email using sendmail or mail command
  if command -v sendmail >/dev/null 2>&1; then
    printf '%s\n' "$email_body" | sendmail -t
  elif command -v mail >/dev/null 2>&1; then
    printf '%s\n' "$email_body" | mail -t
  else
    log "Warning: Neither sendmail nor mail command found. Email not sent."
    log "Install mailutils or a similar package to enable email notifications."
    return 1
  fi

  log "Email sent successfully"
}

emit_match() {
  local hits="$1" url="$2" title="$3"

  # Track match for digest
  track_match "$hits" "$url" "$title"

  # Send per-hit email if configured
  if [[ "$EMAIL_PER" == "hit" && -n "$EMAIL_TO" ]]; then
    local temp_matches=("${MATCHES[@]}")
    MATCHES=("$hits|$url|$title")
    send_email "Craigslist Match Found: ${title}" 1
    MATCHES=("${temp_matches[@]}")
  fi

  case "$FORMAT" in
    plain)
      if [[ -n "$title" ]]; then
        printf 'Match! %s %s - %s\n' "$hits" "$url" "$title"
      else
        printf 'Match! %s %s\n' "$hits" "$url"
      fi
      ;;
    tsv)
      printf 'Match!\t%s\t%s\t%s\n' "$hits" "$url" "$title"
      ;;
    block)
      printf 'Match! %s\n' "$hits"
      printf 'URL:   %s\n' "$url"
      printf 'Title: %s\n' "$title"
      printf '\n'
      ;;
    *)
      die_usage "Unknown format: $FORMAT"
      ;;
  esac
}


main() {
  local opts
  if ! opts=$(getopt -o h --long \
    help,version,city:,section:,pages:,start:,step:,sort:,query:,regex:,output:,append,format:,print-urls,delay:,timeout:,retries:,user-agent:,parser:,verbose,email-to:,email-from:,email-when:,email-per:,html-off \
    -n 'cl-keyword-scrape.sh' -- "$@"); then
    usage >&2
    exit 1
  fi
  eval set -- "$opts"

  while true; do
    case "$1" in
      --city) CITY="$2"; shift 2 ;;
      --section) SECTION="$2"; shift 2 ;;
      --pages) PAGES="$2"; shift 2 ;;
      --start) START="$2"; shift 2 ;;
      --step) STEP="$2"; shift 2 ;;
      --sort) SORT="$2"; shift 2 ;;
      --query) QUERY="$2"; shift 2 ;;
      --regex) REGEX="$2"; shift 2 ;;
      --output) OUTPUT="$2"; shift 2 ;;
      --append) APPEND=1; shift ;;
      --format) FORMAT="$2"; shift 2 ;;
      --print-urls) PRINT_URLS_ONLY=1; shift ;;
      --delay) DELAY="$2"; shift 2 ;;
      --timeout) TIMEOUT="$2"; shift 2 ;;
      --retries) RETRIES="$2"; shift 2 ;;
      --user-agent) USER_AGENT="$2"; shift 2 ;;
      --parser) PARSER="$2"; shift 2 ;;
      --verbose) VERBOSE=1; shift ;;
      --email-to) EMAIL_TO="$2"; shift 2 ;;
      --email-from) EMAIL_FROM="$2"; shift 2 ;;
      --email-when) EMAIL_WHEN="$2"; shift 2 ;;
      --email-per) EMAIL_PER="$2"; shift 2 ;;
      --html-off) HTML_EMAIL=0; shift ;;
      --version) printf '%s\n' "$VERSION"; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done

  need_cmd curl
  need_cmd getopt
  need_cmd awk
  need_cmd sed
  need_cmd grep
  need_cmd sort
  need_cmd mktemp
  need_cmd wc
  need_cmd tee

  [[ "$PAGES" =~ ^[0-9]+$ ]] || die_usage "Invalid --pages: $PAGES"
  [[ "$START" =~ ^[0-9]+$ ]] || die_usage "Invalid --start: $START"
  [[ "$STEP" =~ ^[0-9]+$ ]] || die_usage "Invalid --step: $STEP"
  [[ "$DELAY" =~ ^[0-9]+([.][0-9]+)?$ ]] || die_usage "Invalid --delay: $DELAY"

  # Email validation
  case "$EMAIL_WHEN" in
    never|success|failure|both) ;;
    *) die_usage "Invalid --email-when: $EMAIL_WHEN (must be: never|success|failure|both)" ;;
  esac

  case "$EMAIL_PER" in
    run|hit) ;;
    *) die_usage "Invalid --email-per: $EMAIL_PER (must be: run|hit)" ;;
  esac

  if [[ "$EMAIL_WHEN" != "never" && -z "$EMAIL_TO" ]]; then
    die_usage "Email notifications enabled but --email-to not specified"
  fi

  if [[ -n "$EMAIL_TO" && "$EMAIL_WHEN" == "never" ]]; then
    log "Warning: --email-to specified but --email-when is 'never'. No emails will be sent."
  fi

  # Set default from address if not specified
  if [[ -n "$EMAIL_TO" && -z "$EMAIL_FROM" ]]; then
    EMAIL_FROM="${USER:-scraper}@$(hostname -f 2>/dev/null || hostname)"
    log "Using default --email-from: $EMAIL_FROM"
  fi

  select_parser

  TMPDIR="$(mktemp -d)"
  local urls_file="${TMPDIR}/urls.txt"
  : > "$urls_file"

  log "Collecting URLs (city=$CITY section=$SECTION pages=$PAGES start=$START step=$STEP sort=$SORT query=$QUERY)"

  local i offset search_url html
  for (( i=0; i<PAGES; i++ )); do
    offset=$(( START + i * STEP ))
    search_url="$(build_search_url "$offset")"
    log "Fetching search page: $search_url"
    html="$(fetch "$search_url")" || die "Failed to fetch search page: $search_url"

    printf '%s' "$html" | extract_listing_urls >> "$urls_file"
    sleep "$DELAY"
  done

  sort -u -o "$urls_file" "$urls_file"
  
  local count
count="$(wc -l < "$urls_file" | tr -d ' ')"
log "Unique listing URLs: $count"
if [[ "$count" -eq 0 ]]; then
  die_usage "No listing URLs found. Craigslist markup likely changed; try --parser htmlq or update selectors."
fi


  if [[ "$PRINT_URLS_ONLY" -eq 1 ]]; then
    cat "$urls_file"
    exit 0
  fi

  if [[ "$APPEND" -eq 1 ]]; then : >> "$OUTPUT"; else : > "$OUTPUT"; fi

  log "Found $(wc -l < "$urls_file" | tr -d ' ') unique URLs. Fetching posts..."

  local url post_html title body content hits line
  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    log "Fetching post: $url"

    if ! post_html="$(fetch "$url")"; then
      log "Fetch failed: $url"
      track_error "Failed to fetch: $url"
      sleep "$DELAY"
      continue
    fi

    title="$(printf '%s' "$post_html" | extract_title)"
    body="$(printf '%s' "$post_html" | extract_body_text)"
    content="${title}"$'\n'"${body}"

    if hits="$(collect_hits "$content")"; then
      emit_match "$hits" "$url" "$title" | tee -a "$OUTPUT" >/dev/null
    fi

    sleep "$DELAY"
  done < "$urls_file"

  log "Done. Output: $OUTPUT"

  # Send digest email if configured for "per run"
  if [[ "$EMAIL_PER" == "run" && -n "$EMAIL_TO" ]]; then
    local match_count="${#MATCHES[@]}"
    local error_count="${#ERRORS[@]}"

    if [[ "$match_count" -gt 0 ]]; then
      send_email "Craigslist Scraper: ${match_count} matches found" 1
    elif [[ "$error_count" -gt 0 ]]; then
      send_email "Craigslist Scraper: Completed with ${error_count} errors" 0
    else
      send_email "Craigslist Scraper: No matches found" 1
    fi
  fi
}

main "$@"
