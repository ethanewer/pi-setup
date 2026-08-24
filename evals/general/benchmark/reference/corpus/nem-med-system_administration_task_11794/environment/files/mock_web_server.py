#!/usr/bin/env python3
import socket
import time
import os
import sys

# Simple mock web server for testing
if __name__ == "__main__":
    # Write PID file
    pid_file = f'/tmp/mock_service_web_server.pid'
    with open(pid_file, 'w') as f:
        f.write(str(os.getpid()))
    
    print(f"Mock web server starting on port 8080, PID: {os.getpid()}")
    
    # Simple HTTP server that responds to /health
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('localhost', 8080))
    server.listen(5)
    
    try:
        while True:
            conn, addr = server.accept()
            request = conn.recv(1024).decode()
            if 'GET /health' in request:
                response = 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nALIVE'
                conn.send(response.encode())
            else:
                response = 'HTTP/1.1 404 Not Found\r\n\r\n'
                conn.send(response.encode())
            conn.close()
    except KeyboardInterrupt:
        pass
    finally:
        server.close()
        os.remove(pid_file)