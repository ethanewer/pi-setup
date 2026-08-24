#!/usr/bin/env python3
import socket
import time
import os
import sys

# Simple mock database server for testing
if __name__ == "__main__":
    # Write PID file
    pid_file = f'/tmp/mock_service_database.pid'
    with open(pid_file, 'w') as f:
        f.write(str(os.getpid()))
    
    print(f"Mock database starting on port 5432, PID: {os.getpid()}")
    
    # Simple socket server
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('localhost', 5432))
    server.listen(5)
    
    try:
        while True:
            conn, addr = server.accept()
            # Simple response to indicate server is alive
            conn.send(b'READY')
            conn.close()
            time.sleep(0.1)
    except KeyboardInterrupt:
        pass
    finally:
        server.close()
        os.remove(pid_file)