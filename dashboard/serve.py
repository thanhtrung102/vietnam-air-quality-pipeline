"""
Local dev server for the Leaflet dashboard — fully offline, no AWS/Athena.

Injects  window.AQI_API_URL = "/api"  into index.html, then serves the API the dashboard expects:
    GET /api                      -> demo_data.json            (the map GeoJSON)
    GET /api/analytics/health     -> demo_analytics/health.json
    GET /api/analytics/seasonal   -> demo_analytics/seasonal.json
    GET /api/analytics/compliance -> demo_analytics/compliance.json
    GET /api/analytics/forecast   -> demo_analytics/forecast.json
The analytics JSON is generated deterministically by make_demo_analytics.py (run it once).

Usage:
    cd dashboard
    python serve.py                 # http://localhost:8000
    PORT=8090 python serve.py       # override port (avoid clashes with other local stacks)
"""

import http.server
import os

PORT = int(os.getenv("PORT", "8000"))
HERE = os.path.dirname(os.path.abspath(__file__))
INJECT = b'<script>window.AQI_API_URL = "/api";</script>'

# API route -> file on disk. Map base ("/api") returns the GeoJSON; analytics sub-routes the marts.
API_ROUTES = {
    "/api": "demo_data.json",
    "/api/analytics/health": "demo_analytics/health.json",
    "/api/analytics/seasonal": "demo_analytics/seasonal.json",
    "/api/analytics/compliance": "demo_analytics/compliance.json",
    "/api/analytics/forecast": "demo_analytics/forecast.json",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def _send_bytes(self, content, ctype):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        if path in ("/", "/index.html"):
            with open(os.path.join(HERE, "index.html"), "rb") as f:
                content = f.read().replace(b"</head>", INJECT + b"\n</head>", 1)
            return self._send_bytes(content, "text/html; charset=utf-8")
        if path in API_ROUTES:
            fpath = os.path.join(HERE, API_ROUTES[path])
            if os.path.exists(fpath):
                with open(fpath, "rb") as f:
                    return self._send_bytes(f.read(), "application/json")
            self.send_error(404, f"demo data missing: {API_ROUTES[path]} (run make_demo_analytics.py)")
            return
        super().do_GET()

    def log_message(self, fmt, *args):
        print(f"  {self.address_string()} {fmt % args}")


if __name__ == "__main__":
    os.chdir(HERE)
    with http.server.HTTPServer(("", PORT), Handler) as httpd:
        print(f"Serving dashboard at http://localhost:{PORT}  (API at /api, analytics at /api/analytics/*)")
        print("Press Ctrl+C to stop.")
        httpd.serve_forever()
