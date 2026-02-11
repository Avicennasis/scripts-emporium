import requests
from bs4 import BeautifulSoup
import concurrent.futures
import time
import json
import os
import argparse
import sys
from datetime import datetime
import threading
import collections
from urllib.parse import urlparse

# ==========================================
# Default Configuration Constants
# ==========================================
DEFAULT_INPUT_FILE = 'Links.txt'
DEFAULT_DATA_FILE = 'report_data.json'
DEFAULT_BATCH_SIZE = 25
DEFAULT_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
DEFAULT_TIMEOUT = 10

def get_args():
    """
    Parse command-line arguments to allow runtime configuration.
    """
    parser = argparse.ArgumentParser(description="Link Audit Tool Scanner: Scans URLs and generates a JSON report.")
    
    parser.add_argument('--input', '-i', default=DEFAULT_INPUT_FILE, 
                        help=f"Path to input text file containing URLs (default: {DEFAULT_INPUT_FILE})")
    
    parser.add_argument('--output', '-o', default=DEFAULT_DATA_FILE, 
                        help=f"Path to output JSON data file (default: {DEFAULT_DATA_FILE})")
    
    parser.add_argument('--batch-size', '-b', type=int, default=DEFAULT_BATCH_SIZE, 
                        help=f"Number of concurrent requests (default: {DEFAULT_BATCH_SIZE})")
    
    parser.add_argument('--user-agent', '-u', default=DEFAULT_USER_AGENT, 
                        help="User-Agent string to use for HTTP requests")
    
    parser.add_argument('--timeout', '-t', type=int, default=DEFAULT_TIMEOUT, 
                        help=f"Request timeout in seconds (default: {DEFAULT_TIMEOUT})")

    parser.add_argument('--verbose', '-v', action='store_true', 
                        help="Enable verbose output for debugging")
    
    parser.add_argument('--recheck', '-r', action='store_true', 
                        help="Re-scan URLs from existing JSON output file instead of input text file")

    return parser.parse_args()

def get_timestamp():
    """Returns current timestamp as a string."""
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def log(msg, verbose_flag=False, is_verbose_msg=False):
    """
    Helper function for logging.
    If is_verbose_msg is True, only print if verbose_flag is True.
    """
    if is_verbose_msg and not verbose_flag:
        return
    print(msg)

def check_link(url, user_agent, timeout, verbose=False):
    """
    Performs the audit on a single URL.
    1. Tries HEAD request first for speed.
    2. Falls back to GET if HEAD implies failure, or if we need content (HTML title).
    3. Extracts Title, Meta Description, or H1 if it's an HTML page.
    4. Records redirect chains and specific error types (DNS, SSL, Timeout).
    """
    result = {
        'id': None, 
        'url': url,
        'status_code': None,
        'redirects': [],
        'error': None,
        'title': None,
        'description': None,
        'content_type': None,
        'timestamp': get_timestamp()
    }
    
    try:
        headers = {
            'User-Agent': user_agent,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.5',
            'Referer': 'https://www.google.com/'
        }
        
        cookies = {
            'CONSENT': 'YES+cb',
            'SOCS': 'CAESHAgBEhJnd3NfMjAyMzA4MTAtMF9SQzIaAmVuIAEaBgiAo_CmBg'
        }

        # Optimized Timeout: (Connect, Read)
        # Fail fast on connection (3s), wait longer for response (timeout val)
        request_timeout = (3.05, timeout)
        
        # --- Attempt 1: HEAD Request ---
        if verbose: log(f"Checking {url} (HEAD)...", verbose, True)
        try:
            r = requests.head(url, headers=headers, cookies=cookies, timeout=request_timeout, allow_redirects=True)
            head_status = r.status_code
        except requests.RequestException as e:
            if verbose: log(f"HEAD failed for {url}: {e}", verbose, True)
            head_status = None
            r = None

        # --- Decide if GET is needed ---
        need_get = False
        if r is None:
            need_get = True 
        elif r.status_code in [405, 403, 404]:
             need_get = True 
        elif 200 <= r.status_code < 300:
             need_get = True 
        
        # --- Attempt 2: GET Request ---
        if need_get:
             if verbose: log(f"Fetching content for {url} (GET)...", verbose, True)
             try:
                r = requests.get(url, headers=headers, cookies=cookies, timeout=request_timeout, stream=True)
             except requests.RequestException:
                if r is None: raise
        
        # --- Record Results ---
        result['status_code'] = r.status_code
        if r.history:
            result['redirects'] = [resp.url for resp in r.history]
        
        content_type = r.headers.get('Content-Type', '').lower()
        result['content_type'] = content_type
        
        # --- Extract Metadata (if HTML) ---
        if 200 <= r.status_code < 300:
            if 'text/html' in content_type or 'application/xhtml+xml' in content_type:
                # Read more content (up to 1MB)
                content = b""
                for chunk in r.iter_content(chunk_size=8192):
                    content += chunk
                    if len(content) > 1024 * 1024: 
                        break
                
                soup = BeautifulSoup(content, 'html.parser')
                
                if soup.title and soup.title.string:
                    result['title'] = soup.title.string.strip()
                
                if not result['title']:
                    og_title = soup.find('meta', attrs={'property': 'og:title'})
                    if og_title and og_title.get('content'):
                         result['title'] = og_title['content'].strip()

                meta = soup.find('meta', attrs={'name': 'description'}) or soup.find('meta', attrs={'property': 'og:description'})
                if meta and meta.get('content'):
                    result['description'] = meta['content'].strip()
                
                if not result['description']:
                    h1 = soup.find('h1')
                    if h1:
                        h1_text = h1.get_text(" ", strip=True)
                        if len(h1_text) > 100: h1_text = h1_text[:100] + "..."
                        result['description'] = f"Heading: {h1_text}"
            else:
                size = r.headers.get('Content-Length', 'unknown size')
                result['description'] = f"File: {content_type} ({size} bytes)"
        else:
            result['description'] = f"HTTP {r.status_code}"

    # --- Error Handling ---
    except requests.exceptions.Timeout:
        result['error'] = "Timeout"
    except requests.exceptions.SSLError:
        result['error'] = "TLS/SSL Error"
    except requests.exceptions.ConnectionError as e:
        msg = str(e)
        if "NameResolutionError" in msg or "gaierror" in msg or "NXDOMAIN" in msg:
             result['error'] = "DNS Error (NXDOMAIN)"
        else:
             result['error'] = "Connection Failed"
    except Exception as e:
        result['error'] = str(e)

    if verbose: log(f"Finished {url}: {result['status_code'] or result['error']}", verbose, True)
    return result

def handle_existing_file(filepath):
    """
    Prompts user if file exists to avoid accidental data loss.
    Returns: action ('overwrite', 'append', 'cancel'), final_filepath
    """
    while os.path.exists(filepath):
        print(f"\nOutput file '{filepath}' already exists.")
        choice = input("Do you want to (O)verwrite, (A)ppend, (R)ename, or (C)ancel? ").lower().strip()
        
        if choice == 'o':
            return 'overwrite', filepath
        elif choice == 'a':
            return 'append', filepath
        elif choice == 'r':
            new_path = input("Enter new filename: ").strip()
            if not new_path:
                print("Invalid filename.")
                continue
            if new_path == filepath:
                continue
            filepath = new_path
            # Check loop again for new path
        elif choice == 'c':
            return 'cancel', None
        else:
            print("Invalid choice. Please enter O, A, R, or C.")
            
    return 'overwrite', filepath

def interleave_urls(urls):
    """
    Reorders URLs to minimize hitting the same domain consecutively.
    """
    domain_map = collections.defaultdict(list)
    for u in urls:
        try:
            domain = urlparse(u).netloc
        except:
            domain = 'unknown'
        domain_map[domain].append(u)
    
    # Round-robin selection
    interleaved = []
    while domain_map:
        keys = list(domain_map.keys())
        for k in keys:
            interleaved.append(domain_map[k].pop(0))
            if not domain_map[k]:
                del domain_map[k]
    
    return interleaved

def main():
    args = get_args()
    
    print(f"Starting Link Audit Scanner...")
    if args.verbose: print(f"Verbose mode enabled.")
    
    # --- RECHECK MODE: Load URLs from existing JSON ---
    if args.recheck:
        print(f"RECHECK MODE: Re-scanning URLs from {args.output}")
        try:
            with open(args.output, 'r', encoding='utf-8') as f:
                existing_data = json.load(f)
            alphabetical_urls = sorted([item['url'] for item in existing_data])
            print(f"Loaded {len(alphabetical_urls)} URLs from existing JSON.")
        except FileNotFoundError:
            print(f"Error: {args.output} not found. Run a normal scan first.")
            return
        except Exception as e:
            print(f"Error reading JSON: {e}")
            return
        output_file = args.output
        action = 'overwrite'
    else:
        # --- NORMAL MODE: Load URLs from text file ---
        print(f"Input: {args.input}")
        try:
            with open(args.input, 'r', encoding='utf-8') as f:
                raw_lines = [line.strip() for line in f if line.strip() and not line.strip().startswith('#')]
        except FileNotFoundError:
            print(f"Error: {args.input} not found.")
            return

        # De-duplicate and Sort Alphabetically
        alphabetical_urls = sorted(list(set(raw_lines)))
        if len(alphabetical_urls) < len(raw_lines):
            print(f"Cleaned Input: Removed {len(raw_lines) - len(alphabetical_urls)} duplicates.")
        
        # Handle Output Checks
        action, output_file = handle_existing_file(args.output)
        if action == 'cancel':
            print("Operation cancelled.")
            return
    
    print(f"Output: {output_file} ({action})")
    print(f"Batch Size: {args.batch_size}")
    
    # 4. Load Existing Data (if appending)
    existing_data = []
    if action == 'append':
        try:
            with open(output_file, 'r', encoding='utf-8') as f:
                existing_data = json.load(f)
            print(f"Loaded {len(existing_data)} existing records.")
        except Exception as e:
            print(f"Error loading existing JSON: {e}. Starting fresh.")
            existing_data = []

    # 5. Process URLs (Interleaved)
    # We use interleaved order for processing to be polite to servers
    processing_queue = interleave_urls(alphabetical_urls)
    total_urls = len(processing_queue)
    
    print(f"Found {total_urls} unique URLs to scan. Processing in batches of {args.batch_size}...")
    print(f"Optimization: URLs interleaved by domain to distribute load.")
    
    new_results = []
    processed_count = 0
    
    for i in range(0, total_urls, args.batch_size):
        batch = processing_queue[i:i+args.batch_size]
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.batch_size) as executor:
            future_to_url = {executor.submit(check_link, url, args.user_agent, args.timeout, args.verbose): url for url in batch}
            for future in concurrent.futures.as_completed(future_to_url):
                res = future.result()
                new_results.append(res)
        
        processed_count += len(batch)
        print(f"Processed {processed_count}/{total_urls}...")
        
        # Small delay between batches
        if processed_count < total_urls:
            time.sleep(1)

    # 6. Finalize and Save
    # We combine new results with existing
    final_data = existing_data + new_results
    
    # Sort Final Data Logic: 
    # User likes alphabetical inputs. To keep report clean, let's sort by URL.
    final_data.sort(key=lambda x: x['url'])
    
    # Re-assign IDs for consistency (1..N) based on sorted order
    for idx, res in enumerate(final_data):
        res['id'] = idx + 1

    print(f"Saving {len(final_data)} records to {output_file}...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(final_data, f, indent=2)
    
    print(f"Done! Run 'python server.py --data-file {output_file}' to view the report.")

if __name__ == "__main__":
    main()
