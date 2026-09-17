#!/usr/bin/env python3
"""Small CONNECT/HTTP proxy with an explicit hostname allowlist."""
import argparse
import selectors
import socket
import socketserver
from urllib.parse import urlsplit


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(20)
        data = b''
        while b'\r\n\r\n' not in data and len(data) < 65536:
            chunk = self.request.recv(4096)
            if not chunk:
                return
            data += chunk
        line = data.split(b'\r\n', 1)[0].decode('latin1')
        try:
            method, target, _version = line.split(' ', 2)
            if method.upper() == 'CONNECT':
                host, port = target.rsplit(':', 1)
                port = int(port)
            else:
                parsed = urlsplit(target)
                host, port = parsed.hostname, parsed.port or (443 if parsed.scheme == 'https' else 80)
            host = (host or '').lower().rstrip('.')
            if port not in (80, 443) or not any(host == suffix or host.endswith('.' + suffix)
                                                for suffix in self.server.allowed):
                self.request.sendall(b'HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n')
                return
            upstream = socket.create_connection((host, port), timeout=20)
            if method.upper() == 'CONNECT':
                self.request.sendall(b'HTTP/1.1 200 Connection established\r\n\r\n')
            else:
                upstream.sendall(data)
            relay(self.request, upstream)
        except (OSError, ValueError):
            try:
                self.request.sendall(b'HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n')
            except OSError:
                pass


def relay(left, right):
    selector = selectors.DefaultSelector()
    for stream in (left, right):
        stream.setblocking(False)
        selector.register(stream, selectors.EVENT_READ)
    try:
        while True:
            events = selector.select(60)
            if not events:
                return
            for key, _ in events:
                source = key.fileobj
                target = right if source is left else left
                data = source.recv(65536)
                if not data:
                    return
                target.sendall(data)
    finally:
        right.close()


class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket', required=True)
    parser.add_argument('--allow', action='append', required=True)
    args = parser.parse_args()
    try:
        import os
        os.unlink(args.socket)
    except FileNotFoundError:
        pass
    with Server(args.socket, Handler) as server:
        server.allowed = tuple(value.lower().strip('.') for value in args.allow)
        server.serve_forever()


if __name__ == '__main__':
    main()
