"""
Local dev server for the Leaflet dashboard.

Serves dashboard/ with demo_data.json injected as the API data source.
Injects  window.AQI_API_URL = "demo_data.json"  into index.html responses
without modifying the source file.

Usage:
    cd D:/vietnam-air-quality-pipeline/dashboard
    python serve.py

Then open http://localhost:8000 in your browser.
"""

import http.server
import os

PORT = 8000
INJECT = b'<script>window.AQI_API_URL = "demo_data.json";</script>'


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # Only patch index.html
        if self.path in ("/", "/index.html"):
            index_path = os.path.join(os.path.dirname(__file__), "index.html")
            with open(index_path, "rb") as f:
                content = f.read()
            # Inject before </head> so window.AQI_API_URL is set before the
            # main script reads it
            patched = content.replace(b"</head>", INJECT + b"\n</head>", 1)
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(patched)))
            self.end_headers()
            self.wfile.write(patched)
        else:
            super().do_GET()

    def log_message(self, fmt, *args):
        print(f"  {self.address_string()} {fmt % args}")


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    with http.server.HTTPServer(("", PORT), Handler) as httpd:
        print(f"Serving dashboard at http://localhost:{PORT}")
        print("Press Ctrl+C to stop.")
        httpd.serve_forever()
