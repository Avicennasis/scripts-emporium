#!/usr/bin/env python3
"""
Shared helpers for the domx-records scripts (FR-232 / Redmine #49127).

These were copy-pasted byte-for-byte across do_dns_audit.py,
do_dns_audit_grouped.py and lockdown_mail.py. They live here once.

Note: DOClient below is the read-only domains/records client used by the two
audit scripts. lockdown_mail.py uses a different, write-capable DOClient
(dry-run + create/update/delete) and imports only the helper functions.
"""

from __future__ import annotations

import os
import re
import time
from typing import Any, Dict, List, Optional

import requests

API_BASE = "https://api.digitalocean.com/v2"


def load_env_file(env_path: str = ".env") -> Dict[str, str]:
    """
    Load environment variables from a .env file.

    This function provides a simple, dependency-free way to load configuration
    from a .env file without requiring the python-dotenv package. It's designed
    to be a drop-in solution for small scripts that need basic .env support.

    The .env file format supported:
      - KEY=value           (basic assignment)
      - KEY="quoted value"  (quoted values, quotes are stripped)
      - KEY='quoted value'  (single quotes also supported)
      - # comment           (lines starting with # are ignored)
      - Empty lines         (ignored)
      - KEY=                (empty value is valid)

    Parameters:
    -----------
    env_path : str
        Path to the .env file. Defaults to ".env" in the current directory.

    Returns:
    --------
    Dict[str, str]
        Dictionary mapping environment variable names to their values.
        Returns an empty dictionary if the file doesn't exist.

    Notes:
    ------
    - This function does NOT automatically set os.environ; it just returns
      the parsed values. The caller decides what to do with them.
    - Values are stripped of surrounding whitespace and quotes.
    - This is intentionally simple and doesn't handle all edge cases that
      python-dotenv does (like multi-line values or escape sequences).
    """
    env_vars = {}

    # Check if the .env file exists before attempting to read
    if not os.path.isfile(env_path):
        return env_vars

    # Read and parse the .env file line by line
    with open(env_path, "r", encoding="utf-8") as f:
        for line in f:
            # Strip whitespace from both ends of the line
            line = line.strip()

            # Skip empty lines and comments
            if not line or line.startswith("#"):
                continue

            # Split on the first '=' only (values can contain '=')
            if "=" in line:
                key, value = line.split("=", 1)

                # Clean up the key (remove whitespace)
                key = key.strip()

                # Clean up the value (remove whitespace and surrounding quotes)
                value = value.strip()

                # Remove surrounding quotes if present (both single and double)
                if len(value) >= 2:
                    if (value[0] == value[-1]) and value[0] in ('"', "'"):
                        value = value[1:-1]

                env_vars[key] = value

    return env_vars

def get_token(args_token: Optional[str]) -> Optional[str]:
    """
    Retrieve the DigitalOcean API token from available sources.

    This function implements a priority-based token retrieval system that
    checks multiple sources in order, allowing flexible configuration:

    Priority Order:
    1. .env file (DO_TOKEN=...)     - Most secure for local development
    2. Environment variable         - Standard for CI/CD and containers
    3. Command-line argument        - Convenient for one-off runs

    Parameters:
    -----------
    args_token : Optional[str]
        Token value from command-line arguments (--token flag).
        May be None if not provided on command line.

    Returns:
    --------
    Optional[str]
        The API token if found in any source, None otherwise.

    Security Considerations:
    ------------------------
    - .env file: Should have restrictive permissions (chmod 600)
    - Environment variable: Visible in process listings, less secure
    - Command-line: Visible in shell history, least secure

    The .env file approach is recommended for local development because:
    - Not visible in shell history
    - Not visible in process listings
    - Can be excluded from version control via .gitignore
    """
    # Priority 1: Check .env file first (most secure option)
    env_vars = load_env_file()
    if "DO_TOKEN" in env_vars and env_vars["DO_TOKEN"]:
        return env_vars["DO_TOKEN"]

    # Priority 2: Check shell environment variable
    env_token = os.getenv("DO_TOKEN")
    if env_token:
        return env_token

    # Priority 3: Use command-line argument as fallback
    if args_token:
        return args_token

    # No token found in any source
    return None

def normalize_txt_value(s: Optional[str]) -> str:
    """
    Normalize a TXT record value for reliable comparisons.

    Problem:
    --------
    DNS provider UIs and tools often display TXT records with surrounding
    quotes, and users frequently copy-paste these quoted values back into
    DNS management interfaces. This results in literal quote characters
    being stored as part of the record value. Additionally, whitespace
    handling varies between providers.

    For example, these should all be treated as equivalent:
      - v=spf1 -all
      - "v=spf1 -all"
      - 'v=spf1 -all'
      - "v=spf1  -all"  (extra internal space)

    Solution:
    ---------
    This function:
    1. Handles None input gracefully
    2. Strips leading/trailing whitespace
    3. Removes wrapping quote characters (repeatedly, to handle nested quotes)
    4. Collapses multiple internal whitespace to single spaces

    Parameters:
    -----------
    s : Optional[str]
        The raw TXT record value from the DNS API. May be None.

    Returns:
    --------
    str
        Normalized string suitable for comparison. Returns empty string for None.

    Examples:
    ---------
    >>> normalize_txt_value('"v=spf1 -all"')
    'v=spf1 -all'

    >>> normalize_txt_value("v=DMARC1;  p=reject")
    'v=DMARC1; p=reject'

    >>> normalize_txt_value(None)
    ''
    """
    # Handle None input - common when accessing optional dict keys
    if s is None:
        return ""

    # Convert to string and strip outer whitespace
    s = str(s).strip()

    # Repeatedly strip matching quote pairs from both ends
    # This handles cases like: '"value"' or ""value"" (yes, people do this)
    while len(s) >= 2 and ((s[0] == s[-1] == '"') or (s[0] == s[-1] == "'")):
        s = s[1:-1].strip()

    # Collapse all runs of whitespace to single spaces
    # This normalizes "v=spf1   -all" to "v=spf1 -all"
    return " ".join(s.split())

def normalize_host(s: Optional[str]) -> str:
    """
    Normalize hostnames for reliable comparisons.

    Problem:
    --------
    Hostnames in DNS can appear in different formats:
      - Fully Qualified Domain Name (FQDN): mail.example.com.
      - Non-FQDN: mail.example.com
      - Mixed case: Mail.Example.COM

    For comparison purposes, we need a canonical form.

    Solution:
    ---------
    This function:
    1. Handles None input gracefully
    2. Strips whitespace
    3. Converts to lowercase (DNS is case-insensitive)
    4. Removes trailing dot (FQDN notation)

    Parameters:
    -----------
    s : Optional[str]
        The hostname string, possibly in FQDN format. May be None.

    Returns:
    --------
    str
        Normalized lowercase hostname without trailing dot.

    Examples:
    ---------
    >>> normalize_host("mail.invalid.")
    'mail.invalid'

    >>> normalize_host("MAIL.INVALID")
    'mail.invalid'

    >>> normalize_host(None)
    ''
    """
    # Handle None and convert to lowercase
    s = (s or "").strip().lower()

    # Remove trailing dot if present (FQDN notation)
    if s.endswith("."):
        s = s[:-1]

    return s

def parse_tag_value(semi_colon_kv: str, tag: str) -> Optional[str]:
    """
    Parse a tag=value pair from a semicolon-separated policy string.

    Problem:
    --------
    DMARC and other DNS-based policy records use a semicolon-separated
    tag=value format. For example:

      v=DMARC1; p=reject; sp=reject; rua=mailto:reports@example.com

    We need to extract specific tag values (like the 'p' policy or 'rua'
    report address) for analysis.

    Solution:
    ---------
    Uses a regex to find the specified tag anywhere in the string,
    accounting for:
    - Tag at the start of the string
    - Tag after a semicolon (with optional whitespace)
    - Case-insensitive matching
    - Values that may contain various characters (up to the next semicolon)

    Parameters:
    -----------
    semi_colon_kv : str
        The full policy string (e.g., DMARC record value)

    tag : str
        The tag name to search for (e.g., "p", "rua", "adkim")

    Returns:
    --------
    Optional[str]
        The tag's value if found, None otherwise.

    Notes:
    ------
    This is not a full DMARC/SPF parser. It's a "good enough" extractor
    for common tags. Edge cases (like malformed records) may not parse
    correctly, but that's acceptable for audit purposes - we just want
    to flag records that exist and extract basic info.

    Examples:
    ---------
    >>> parse_tag_value("v=DMARC1; p=reject; rua=mailto:x@y.com", "p")
    'reject'

    >>> parse_tag_value("v=DMARC1; p=reject", "rua")
    None
    """
    # Build regex pattern:
    # - (?:^|;\s*) matches either start of string OR semicolon with optional whitespace
    # - {tag}\s*=\s* matches the tag name with optional whitespace around '='
    # - ([^;]+) captures the value (everything up to the next semicolon)
    m = re.search(
        rf"(?:^|;\s*){re.escape(tag)}\s*=\s*([^;]+)",
        semi_colon_kv,
        flags=re.IGNORECASE
    )

    # Return the captured group (trimmed) if found, None otherwise
    return m.group(1).strip() if m else None

class DOClient:
    """
    A minimal DigitalOcean API wrapper for DNS operations.

    Purpose:
    --------
    This class encapsulates all communication with the DigitalOcean API,
    providing a clean interface for listing domains and their DNS records.
    It handles common concerns like:
    - Authentication (Bearer token)
    - Rate limiting (HTTP 429 responses)
    - Transient errors (5xx responses)
    - Pagination (domains and records)

    Design Decisions:
    -----------------
    1. Uses requests.Session for connection reuse (performance)
    2. Implements automatic retry with exponential backoff
    3. Handles pagination transparently (caller gets complete lists)
    4. Raises RuntimeError on unrecoverable failures (clean error handling)

    Attributes:
    -----------
    s : requests.Session
        Persistent HTTP session with authentication headers configured.

    timeout : int
        Request timeout in seconds. Prevents hanging on network issues.

    Usage:
    ------
        client = DOClient("dop_v1_your_token_here")
        domains = client.list_domains()
        for domain in domains:
            records = client.list_records(domain)
    """

    def __init__(self, token: str, timeout: int = 30):
        """
        Initialize the DigitalOcean API client.

        Parameters:
        -----------
        token : str
            DigitalOcean personal access token (starts with "dop_v1_").
            Must have read permissions for Domains.

        timeout : int
            HTTP request timeout in seconds. Default 30s is reasonable for
            API calls but can be increased for slow networks.
        """
        # Create a persistent session for connection reuse
        # This improves performance by reusing TCP connections
        self.s = requests.Session()

        # Configure default headers for all requests
        self.s.headers.update({
            "Authorization": f"Bearer {token}",  # Bearer auth per DO API spec
            "Content-Type": "application/json",   # All responses are JSON
        })

        # Store timeout for use in requests
        self.timeout = timeout

    def req(self, method: str, path: str, **kwargs) -> Dict[str, Any]:
        """
        Perform an HTTP request to the DigitalOcean API with retry logic.

        This method handles the low-level API communication, including:
        - URL construction from path
        - Automatic retry on transient failures
        - Error handling and propagation

        Parameters:
        -----------
        method : str
            HTTP method (GET, POST, PUT, DELETE, etc.)

        path : str
            API endpoint path (e.g., "/domains" or "/domains/example.com/records")
            Will be appended to API_BASE.

        **kwargs : dict
            Additional arguments passed to requests (json=, params=, etc.)

        Returns:
        --------
        Dict[str, Any]
            Parsed JSON response. Returns empty dict for empty responses.

        Raises:
        -------
        RuntimeError
            On HTTP 4xx errors (except 429) or after max retries exhausted.

        Retry Logic:
        ------------
        - Retries on HTTP 429 (rate limit) and 5xx (server errors)
        - Uses exponential backoff: 2, 4, 8, 16, 20 seconds (capped at 20)
        - Maximum 5 attempts before giving up
        """
        # Construct full URL from base and path
        url = f"{API_BASE}{path}"

        # Retry loop with exponential backoff
        for attempt in range(1, 6):  # Attempts 1 through 5
            # Make the HTTP request
            r = self.s.request(method, url, timeout=self.timeout, **kwargs)

            # Check for retryable conditions
            if r.status_code == 429 or (500 <= r.status_code < 600):
                # Calculate wait time with exponential backoff, capped at 20 seconds
                wait = min(2 ** attempt, 20)
                time.sleep(wait)
                continue  # Retry the request

            # Check for non-retryable errors
            if r.status_code >= 400:
                # Raise an exception with details for debugging
                raise RuntimeError(f"{method} {path} failed: {r.status_code} {r.text}")

            # Success! Parse and return the JSON response
            # Handle empty responses (some DELETE endpoints return nothing)
            return r.json() if r.text.strip() else {}

        # All retry attempts exhausted
        raise RuntimeError(f"{method} {path} failed after retries")

    def list_domains(self) -> List[str]:
        """
        Retrieve all domains managed in the DigitalOcean account.

        This method fetches domain names from the Domains API, handling
        pagination automatically. DigitalOcean returns domains in pages
        of up to 200 items.

        Returns:
        --------
        List[str]
            Sorted list of unique domain names (lowercase).
            Empty list if no domains exist.

        Notes:
        ------
        - Domain names are normalized to lowercase for consistency
        - Duplicates are removed (shouldn't happen, but defensive coding)
        - Results are sorted alphabetically for predictable output
        """
        domains: List[str] = []
        page = 1

        # Paginate through all results
        while True:
            # Request current page of domains
            data = self.req("GET", f"/domains?page={page}&per_page=200")

            # Extract domain names from response
            chunk = data.get("domains", [])
            domains.extend([d["name"].lower() for d in chunk if "name" in d])

            # Check for more pages using the links.pages.next field
            pages = (data.get("links") or {}).get("pages") or {}
            if not pages.get("next"):
                break  # No more pages

            page += 1

        # Return sorted, deduplicated list
        return sorted(set(domains))

    def list_records(self, domain: str) -> List[Dict[str, Any]]:
        """
        Retrieve all DNS records for a specific domain zone.

        This method fetches all records from the Domain Records API,
        handling pagination automatically.

        Parameters:
        -----------
        domain : str
            The domain name (e.g., "example.com")

        Returns:
        --------
        List[Dict[str, Any]]
            List of record dictionaries. Each record contains:
            - id: Unique record identifier
            - type: Record type (A, AAAA, CNAME, MX, TXT, NS, SRV, CAA)
            - name: Record name (@ for apex, or subdomain)
            - data: Record value
            - priority: Priority (for MX and SRV records)
            - port, weight: Additional fields for SRV records
            - ttl: Time to live in seconds

        Notes:
        ------
        DigitalOcean uses '@' to represent the zone apex (root domain).
        """
        recs: List[Dict[str, Any]] = []
        page = 1

        # Paginate through all results
        while True:
            # Request current page of records
            data = self.req("GET", f"/domains/{domain}/records?page={page}&per_page=200")

            # Add records to our list
            recs.extend(data.get("domain_records", []))

            # Check for more pages
            pages = (data.get("links") or {}).get("pages") or {}
            if not pages.get("next"):
                break  # No more pages

            page += 1

        return recs
