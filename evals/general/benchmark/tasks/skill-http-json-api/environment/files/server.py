import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/items':
            data = [{"name": "a", "price": 10},
                    {"name": "b", "price": 25},
                    {"name": "c", "price": 5}]
            body = json.dumps(data).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *a):
        pass

HTTPServer(('127.0.0.1', 8080), H).serve_forever()