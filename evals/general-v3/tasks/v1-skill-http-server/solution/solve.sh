#!/bin/bash
set -euo pipefail
cat > /app/serve.py <<'PYEOF'
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/ping':
            body = b'pong'
        elif self.path == '/info':
            body = b'{"app":"bench"}'
        else:
            body = b'not found'
            self.send_response(404)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass

HTTPServer(('127.0.0.1', 8090), H).serve_forever()
PYEOF
python3 /app/serve.py &
sleep 1
curl -s http://127.0.0.1:8090/ping
curl -s http://127.0.0.1:8090/info
echo "server listening on 8090"