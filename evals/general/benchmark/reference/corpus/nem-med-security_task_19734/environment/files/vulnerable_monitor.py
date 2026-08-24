#!/usr/bin/env python3
"""
VULNERABLE SYSTEM MONITOR
Security audit required - this code has command injection vulnerability.
"""

import subprocess
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.parse

class VulnerableMonitorHandler(BaseHTTPRequestHandler):
    """HTTP handler with command injection vulnerability."""
    
    def do_GET(self):
        """Serve simple HTML form."""
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        
        html = """
        <html>
        <body>
            <h1>System Monitor</h1>
            <form method="POST">
                Enter host to ping: <input type="text" name="host"><br>
                <input type="submit" value="Ping">
            </form>
        </body>
        </html>
        """
        self.wfile.write(html.encode())
    
    def do_POST(self):
        """Handle ping request - VULNERABLE TO COMMAND INJECTION."""
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode()
        parsed_data = urllib.parse.parse_qs(post_data)
        
        host = parsed_data.get('host', [''])[0]
        
        if not host:
            self.send_error(400, "Host parameter required")
            return
        
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        
        # VULNERABLE CODE: Direct command concatenation with shell=True
        try:
            # Critical vulnerability: user input directly concatenated
            command = f"ping -c 3 {host}"
            result = subprocess.run(
                command,
                shell=True,  # DANGER: Shell invocation
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                output = f"Ping successful:\n{result.stdout}"
            else:
                output = f"Ping failed:\n{result.stderr}"
                
        except Exception as e:
            output = f"Error: {str(e)}"
        
        # Another vulnerability: returning raw error messages
        self.wfile.write(output.encode())

def run_server(port=8080):
    """Run the vulnerable server."""
    server = HTTPServer(('localhost', port), VulnerableMonitorHandler)
    print(f"Starting vulnerable server on port {port}")
    print("WARNING: This server has command injection vulnerability!")
    server.serve_forever()

if __name__ == '__main__':
    port = 8080
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print(f"Invalid port: {sys.argv[1]}, using default 8080")
    
    run_server(port)