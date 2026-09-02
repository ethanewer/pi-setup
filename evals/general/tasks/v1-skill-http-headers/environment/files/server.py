from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        tok = self.headers.get('X-Token', 'none')
        body = b'ok'
        self.send_response(200)
        self.send_header('X-Recv-Token', tok)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass

HTTPServer(('127.0.0.1', 8080), H).serve_forever()