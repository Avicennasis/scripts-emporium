from http.server import HTTPServer, SimpleHTTPRequestHandler
import json
import os
import urllib.parse
import argparse
import sys

# ==========================================
# Default Configuration
# ==========================================
DEFAULT_PORT = 8000
DEFAULT_DATA_FILE = 'report_data.json'

def get_args():
    """
    Parse command-line arguments for the server.
    """
    parser = argparse.ArgumentParser(description="Link Audit Report Viewer")
    
    parser.add_argument('--port', '-p', type=int, default=DEFAULT_PORT, 
                        help=f"Port to serve on (default: {DEFAULT_PORT})")
    
    parser.add_argument('--data-file', '-d', default=DEFAULT_DATA_FILE, 
                        help=f"Path to JSON data file to serve/modify (default: {DEFAULT_DATA_FILE})")
    
    parser.add_argument('--verbose', '-v', action='store_true', 
                        help="Log all requests to console")

    return parser.parse_args()

class ReportHandler(SimpleHTTPRequestHandler):
    """
    Custom Handler to serve both the static HTML/JS Report and the JSON API.
    """
    
    def log_message(self, format, *args):
        """Override to control logging based on verbose flag."""
        if hasattr(self, 'verbose') and self.verbose:
            sys.stderr.write("%s - - [%s] %s\n" %
                             (self.client_address[0],
                              self.log_date_time_string(),
                              format%args))

    def do_GET(self):
        """Handle GET requests (Static Files + API)."""
        
        # 1. Serve root as index.html
        if self.path == '/' or self.path == '/index.html':
            self.path = 'index.html'
            return SimpleHTTPRequestHandler.do_GET(self)
        
        # 2. API: Get Data
        if self.path == '/api/data':
            try:
                if os.path.exists(self.data_file):
                    with open(self.data_file, 'r', encoding='utf-8') as f:
                        data = f.read()
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(data.encode())
                else:
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(b'[]')
            except Exception as e:
                self.send_error(500, str(e))
            return

        # 3. Default: Serve other static files
        return SimpleHTTPRequestHandler.do_GET(self)

    def do_DELETE(self):
        """Handle DELETE requests (API Clean-up)."""
        
        if self.path.startswith('/api/remove'):
            try:
                query = urllib.parse.urlparse(self.path).query
                params = urllib.parse.parse_qs(query)
                target_id = params.get('id', [None])[0]
                
                if target_id:
                    if os.path.exists(self.data_file):
                        with open(self.data_file, 'r', encoding='utf-8') as f:
                            data = json.load(f)
                        
                        # Filter (Delete)
                        original_len = len(data)
                        new_data = [item for item in data if str(item.get('id')) != str(target_id)]
                        
                        if len(new_data) < original_len:
                            with open(self.data_file, 'w', encoding='utf-8') as f:
                                json.dump(new_data, f, indent=2)
                        
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(b'{"status": "ok"}')
                    else:
                        self.send_error(404, "Data file not found")
                else:
                    self.send_error(400, "Missing ID")
            except Exception as e:
                self.send_error(500, str(e))
            return
        
        self.send_error(405, "Method not allowed")

def main():
    args = get_args()
    
    # Inject config into the Handler class 
    ReportHandler.data_file = args.data_file
    ReportHandler.verbose = args.verbose
    
    print(f"Starting Link Audit Server...")
    print(f"Port: {args.port}")
    print(f"Serving Data: {args.data_file}")
    if args.verbose: print("Verbose logging enabled.")
    print(f"Open http://localhost:{args.port} in your browser.")
    print("Press Ctrl+C to stop.")
    
    httpd = HTTPServer(('localhost', args.port), ReportHandler)
    
    # Robust Shutdown Handling
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutdown signal received. Stopping server...")
    except Exception as e:
        print(f"\nError: {e}")
    finally:
        httpd.server_close()
        print("Server socket closed.")

if __name__ == "__main__":
    main()
