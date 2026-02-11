#!/usr/bin/env python3
"""
Craigslist Keyword Watcher (Modern Python 3)

This script watches Craigslist search results for new posts and alerts you
when any post body contains one of your keywords.

Key features:
- Uses Craigslist HTML search (not RSS) and parses result links
- Fetches each post page and extracts the posting body
- Matches keywords case-insensitively using a compiled regex
- Sends alerts via local sendmail/ssmtp (no SMTP creds in this script)
- De-dupes alerts across runs using a local JSON "seen" file
- Supports looping (polling), pagination, dry-run, throttling, and debug mail logs

Dependencies:
    pip install requests beautifulsoup4

Environment variables:
    ALERT_TO      Required. Destination email address (or email-to-SMS gateway).
    ALERT_FROM    Optional. From address. Default: craigslist-watcher@localhost
    MAIL_DEBUG    Optional. If "1", runs sendmail/ssmtp with verbose output and prints it.

Examples:
    export ALERT_TO="you@gmail.com"
    export ALERT_FROM="you@gmail.com"
    python3 craigslist_watch.py --region boston --category gms --keywords "mario,ps5,nintendo"

    # Poll every 5 minutes
    python3 craigslist_watch.py --region boston --category gms --keywords "mario,ps5" --loop 300

    # Dry-run prints matches instead of emailing
    python3 craigslist_watch.py --region boston --category gms --keywords "mario,ps5" --dry-run
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from email.message import EmailMessage
from pathlib import Path
from typing import Iterable
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup


# -----------------------------
# Data structures
# -----------------------------

@dataclass(frozen=True)
class Listing:
    """Represents a single Craigslist listing discovered from search results."""
    id: str        # numeric post id if present, else fallback to URL
    title: str
    link: str      # absolute URL


# -----------------------------
# HTTP helpers
# -----------------------------

DEFAULT_HEADERS = {
    # A realistic User-Agent helps reduce bot-filter false positives.
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/122.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}

# Craigslist sometimes returns an HTML block page with this message.
BLOCKED_MARKER = "Your request has been blocked"


def http_get_text(
    session: requests.Session,
    url: str,
    *,
    params: dict | None = None,
    timeout: float = 20.0
) -> str:
    """
    Fetch a URL and return response text.

    - Uses a session for connection reuse (faster + less noisy).
    - Raises requests.HTTPError on non-2xx responses.
    - Detects Craigslist "blocked" page and raises a clear runtime error.
    """
    resp = session.get(url, params=params, headers=DEFAULT_HEADERS, timeout=timeout)
    resp.raise_for_status()

    text = resp.text
    if BLOCKED_MARKER in text:
        raise RuntimeError(f"Craigslist returned a blocked page for URL: {resp.url}")

    return text


# -----------------------------
# Parsing search results (HTML)
# -----------------------------

# Typical post URLs end in /<post_id>.html
POST_ID_RE = re.compile(r"/(\d+)\.html(?:\?|$)")


def listing_id_from_url(url: str) -> str:
    """
    Extract the numeric post ID from a Craigslist listing URL.

    Example:
      https://boston.craigslist.org/gbs/gms/d/waltham-title/7812345678.html

    If no numeric ID is found, fall back to using the URL as an identifier.
    """
    m = POST_ID_RE.search(url)
    return m.group(1) if m else url


def is_same_site(url: str, site_root: str) -> bool:
    """
    Basic sanity check: keep links within the same Craigslist site root.
    """
    try:
        return urlparse(url).netloc == urlparse(site_root).netloc
    except Exception:
        return False


def parse_search_results(html: str, site_root: str) -> list[Listing]:
    """
    Parse a Craigslist search results HTML page and return a list of listings.

    Craigslist markup has changed over time. We support multiple layouts:
    - Newer: li.cl-static-search-result
    - Older:  li.result-row
    - Fallback: scan all anchors for plausible .html listing links

    Args:
        html:      Raw HTML of the search results page
        site_root: e.g. "https://boston.craigslist.org/"

    Returns:
        List[Listing] with unique links (deduped).
    """
    soup = BeautifulSoup(html, "html.parser")

    listings: list[Listing] = []
    seen_links: set[str] = set()

    # New-ish layout
    rows = soup.select("li.cl-static-search-result")
    # Older layout fallback
    if not rows:
        rows = soup.select("li.result-row")

    def add_listing(href: str, title_text: str) -> None:
        """Normalize, dedupe, and append a listing."""
        link = urljoin(site_root, href)

        # Only consider actual post pages
        if not link.endswith(".html"):
            return
        if not is_same_site(link, site_root):
            return
        if link in seen_links:
            return

        seen_links.add(link)
        listings.append(
            Listing(
                id=listing_id_from_url(link),
                title=title_text.strip() or "Craigslist match",
                link=link,
            )
        )

    if rows:
        for row in rows:
            a = row.find("a", href=True)
            if not a:
                continue

            title = a.get_text(" ", strip=True)
            add_listing(a["href"], title)

        return listings

    # Final fallback: scan all anchors for plausible listing links
    for a in soup.find_all("a", href=True):
        title = a.get_text(" ", strip=True)
        add_listing(a["href"], title)

    return listings


# -----------------------------
# Parsing post pages + keyword matching
# -----------------------------

def extract_post_text(html: str) -> str:
    """
    Extract the posting body text from an individual Craigslist post page.

    Craigslist posts typically store the main body in:
      <section id="postingbody"> ... </section>

    Returns plain text. If structure changes or body is missing, returns "".
    """
    soup = BeautifulSoup(html, "html.parser")
    body = soup.select_one("section#postingbody")
    if not body:
        return ""

    text = body.get_text(separator=" ", strip=True)
    # Craigslist sometimes prepends this boilerplate phrase.
    return text.replace("QR Code Link to This Post", "").strip()


def compile_keyword_regex(keywords: Iterable[str]) -> re.Pattern:
    """
    Build one case-insensitive regex that matches any keyword.

    Using a single compiled regex is faster and cleaner than repeated `.find()`.
    """
    cleaned = [k.strip() for k in keywords if k.strip()]
    if not cleaned:
        return re.compile(r"a^")  # matches nothing

    parts = [re.escape(k) for k in cleaned]
    return re.compile(r"(" + "|".join(parts) + r")", re.IGNORECASE)


# -----------------------------
# Seen-state persistence (dedupe)
# -----------------------------

def load_seen(path: Path) -> set[str]:
    """
    Load a JSON list of listing IDs already processed.

    This prevents duplicate notifications across runs.
    """
    if not path.exists():
        return set()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, list):
            return set(map(str, data))
    except Exception:
        # If file is corrupted, we fail open (treat as empty).
        pass
    return set()


def save_seen(path: Path, seen: set[str]) -> None:
    """Save processed listing IDs to disk as JSON."""
    path.write_text(json.dumps(sorted(seen), indent=2), encoding="utf-8")


# -----------------------------
# Alerting via local sendmail/ssmtp
# -----------------------------

def send_alert(subject: str, body: str) -> None:
    """
    Send an alert using the system's local mail sender.

    On your Ubuntu box, "sendmail" is typically provided by /usr/sbin/ssmtp.
    We intentionally do NOT store SMTP credentials in this script.

    Environment:
        ALERT_TO   (required) recipient email (or email-to-SMS gateway)
        ALERT_FROM (optional) From header
        MAIL_DEBUG (optional) if "1", run mailer in verbose mode and print logs

    Implementation detail:
    - We pass the recipient as a command argument (works with ssmtp sendmail emulation)
    - We still include proper headers (From/To/Subject) inside the message
    """
    alert_to = os.getenv("ALERT_TO", "").strip()
    alert_from = os.getenv("ALERT_FROM", "craigslist-watcher@localhost").strip()
    debug = os.getenv("MAIL_DEBUG", "0") == "1"

    if not alert_to:
        raise RuntimeError("Missing ALERT_TO (e.g. you@gmail.com or 6175551212@txt.att.net)")

    msg = EmailMessage()
    msg["From"] = alert_from
    msg["To"] = alert_to
    msg["Subject"] = subject
    msg.set_content(body)

    # Prefer "sendmail" if available (commonly a wrapper to ssmtp/msmtp/postfix).
    sendmail = shutil.which("sendmail") or shutil.which("ssmtp")
    if not sendmail:
        raise RuntimeError("Couldn't find sendmail or ssmtp on PATH")

    # For ssmtp sendmail emulation, recipient as an argument is the most reliable.
    cmd = [sendmail]
    if debug:
        cmd.append("-v")
    # Some sendmail implementations accept -i; ssmtp generally ignores unknown flags,
    # so we only include -i if it looks like a real sendmail binary.
    if os.path.basename(sendmail) == "sendmail":
        cmd.append("-i")
    cmd.append(alert_to)

    p = subprocess.run(cmd, input=msg.as_bytes(), capture_output=True)

    if debug:
        print("sendmail cmd:", " ".join(cmd))
        print("returncode:", p.returncode)
        print("stdout:\n", p.stdout.decode(errors="replace"))
        print("stderr:\n", p.stderr.decode(errors="replace"))

    p.check_returncode()


# -----------------------------
# Main workflow
# -----------------------------

def build_search_url(region: str, category: str) -> str:
    """Build a Craigslist search URL for a given region and category."""
    return f"https://{region}.craigslist.org/search/{category}"


def run_once(
    region: str,
    category: str,
    keywords: list[str],
    query: str | None,
    pages: int,
    page_size: int,
    seen_file: Path,
    sleep_seconds: float,
    dry_run: bool,
) -> int:
    """
    Run a single scan pass:
      1) Fetch N pages of search results (offset pagination with 's')
      2) Parse listings from HTML
      3) For new listings, fetch post pages and scan body text
      4) Alert on keyword matches
      5) Save seen-state
      6) Print an informative summary (no more silent exits)

    Returns:
        Number of alerts sent (0 if none).
    """
    site_root = f"https://{region}.craigslist.org/"
    search_url = build_search_url(region, category)

    kw_re = compile_keyword_regex(keywords)
    seen = load_seen(seen_file)

    total_found = 0
    already_seen = 0
    processed_new = 0
    matched = 0
    alerts_sent = 0

    with requests.Session() as session:
        all_listings: list[Listing] = []

        # Pull multiple search pages (page 0 has no offset; later pages use s=<offset>)
        for page in range(max(1, pages)):
            offset = page * page_size
            params: dict[str, object] = {"sort": "date"}
            if query:
                params["query"] = query
            if offset:
                params["s"] = offset

            html = http_get_text(session, search_url, params=params)
            listings = parse_search_results(html, site_root)

            all_listings.extend(listings)
            time.sleep(sleep_seconds)

        # Dedupe across pages by listing id (some overlap happens in paging)
        by_id: dict[str, Listing] = {}
        for lst in all_listings:
            by_id.setdefault(lst.id, lst)

        listings_unique = list(by_id.values())
        total_found = len(listings_unique)

        for listing in listings_unique:
            if listing.id in seen:
                already_seen += 1
                continue

            processed_new += 1
            # Mark as seen early to avoid repeats even if something fails mid-run
            seen.add(listing.id)

            try:
                post_html = http_get_text(session, listing.link)
            except Exception as e:
                print(f"[skip] could not fetch post: {listing.link} ({e})", file=sys.stderr)
                time.sleep(sleep_seconds)
                continue

            post_text = extract_post_text(post_html)
            if not post_text:
                time.sleep(sleep_seconds)
                continue

            m = kw_re.search(post_text)
            if m:
                matched += 1
                matched_word = m.group(0)

                subject = f"Craigslist match: {matched_word}"
                message_body = (
                    f"{listing.title}\n"
                    f"{listing.link}\n\n"
                    f"Matched: {matched_word}\n"
                )

                if dry_run:
                    print(f"[dry-run] match '{matched_word}' -> {listing.link}")
                else:
                    send_alert(subject, message_body)
                    print(f"[alert] match '{matched_word}' -> {listing.link}")
                    alerts_sent += 1

            time.sleep(sleep_seconds)

    save_seen(seen_file, seen)

    # Summary output so the script doesn't exit silently
    if processed_new == 0:
        print(f"No new posts to scan (found {total_found}, already seen {already_seen}); nothing to send.")
    elif alerts_sent == 0:
        if dry_run:
            print(f"[dry-run] Scanned {processed_new} new posts (found {total_found}, already seen {already_seen}); "
                  f"no keyword matches; nothing would be sent.")
        else:
            print(f"Scanned {processed_new} new posts (found {total_found}, already seen {already_seen}); "
                  f"no keyword matches; nothing to send via email.")
    else:
        if dry_run:
            print(f"[dry-run] Scanned {processed_new} new posts; matches={matched}; would-send={matched}.")
        else:
            print(f"Scanned {processed_new} new posts; matches={matched}; emails-sent={alerts_sent}.")

    return alerts_sent


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Craigslist keyword watcher (HTML search + post fetch + local sendmail/ssmtp)."
    )
    parser.add_argument("--region", default="boston", help="Craigslist region subdomain (default: boston)")
    parser.add_argument("--category", default="gms", help="Craigslist category path (default: gms)")
    parser.add_argument("--query", default=None, help="Optional search query string")
    parser.add_argument(
        "--keywords",
        default="mario,ps3,ps4,xbox,gameboy,linux,sega,brewing",
        help="Comma-separated keywords to match",
    )
    parser.add_argument("--seen-file", default="seen_craigslist.json", help="JSON file storing seen listing IDs")
    parser.add_argument("--pages", type=int, default=1, help="How many search pages to scan (default: 1)")
    parser.add_argument("--page-size", type=int, default=120, help="Pagination step size (default: 120)")
    parser.add_argument("--sleep", type=float, default=1.5, help="Seconds to sleep between requests (default: 1.5)")
    parser.add_argument("--loop", type=int, default=0, help="If >0, rerun every N seconds")
    parser.add_argument("--dry-run", action="store_true", help="Print matches; do not send email")

    args = parser.parse_args()

    keywords = [k.strip() for k in args.keywords.split(",") if k.strip()]
    seen_file = Path(args.seen_file)

    if args.loop and args.loop > 0:
        while True:
            run_once(
                region=args.region,
                category=args.category,
                keywords=keywords,
                query=args.query,
                pages=args.pages,
                page_size=args.page_size,
                seen_file=seen_file,
                sleep_seconds=args.sleep,
                dry_run=args.dry_run,
            )
            time.sleep(args.loop)
    else:
        run_once(
            region=args.region,
            category=args.category,
            keywords=keywords,
            query=args.query,
            pages=args.pages,
            page_size=args.page_size,
            seen_file=seen_file,
            sleep_seconds=args.sleep,
            dry_run=args.dry_run,
        )


if __name__ == "__main__":
    main()
