"""httpkit — a minimal loopback HTTP framework stub for this bench.

Self-contained and stdlib-only (http.server). Binds a fixed loopback host
only. The exam service (/app/token_service.py) registers a path -> handler
table and serves forever.

This is a framework stub, not part of the deliverable; treat it as
read-only. Handlers receive a Request and return a Response (or a plain
JSON-serializable dict, which is wrapped into a 200 Response).

API:
    serve(host, port, handlers)          run forever
    Request: .method .path .query .headers .body_bytes
             .json() -> parsed JSON body  (raises HttpError 400 on malformed)
    Response(status, payload, headers)   payload is JSON-serializable
    HttpError(status, code, message)     raise from a handler
    error(status, code, message)         helper -> Response
"""

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


class HttpError(Exception):
    """Raised by a handler to short-circuit with a JSON error body."""

    def __init__(self, status, code, message):
        super().__init__(message)
        self.status = int(status)
        self.code = code
        self.message = message


class Request:
    def __init__(self, method, path, query, headers, body_bytes):
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body_bytes = body_bytes

    def json(self):
        """Decode the body as JSON.

        Raises HttpError(400, "bad_request", ...) when the body is not valid
        JSON. An empty body parses as None.
        """
        raw = (self.body_bytes or b"").decode("utf-8", "replace").strip()
        if raw == "":
            raw = "null"
        try:
            return json.loads(raw)
        except ValueError as exc:
            raise HttpError(400, "bad_request", "malformed JSON body") from exc


class Response:
    def __init__(self, status=200, payload=None, headers=None):
        self.status = int(status)
        self.payload = payload
        self.headers = dict(headers) if headers else {}


def error(status, code, message):
    return Response(status, {"error": {"code": code, "message": message}})


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "httpkit/1.0"

    def _dispatch(self):
        parsed = urlsplit(self.path)
        query = parse_qs(parsed.query)
        length = 0
        raw_len = self.headers.get("Content-Length")
        if raw_len is not None:
            try:
                length = int(raw_len)
            except ValueError:
                length = 0
        body = self.rfile.read(length) if length > 0 else b""
        req = Request(
            self.command, parsed.path, query,
            {k.lower(): v for k, v in self.headers.items()}, body,
        )
        handler = self.server.service_handlers.get(parsed.path)
        if handler is None:
            self._send(error(404, "not_found", "unknown endpoint"))
            return
        try:
            resp = handler(req)
            if not isinstance(resp, Response):
                resp = Response(200, resp)
            self._send(resp)
        except HttpError as exc:
            self._send(error(exc.status, exc.code, exc.message))
        except Exception as exc:  # defensive: never kill the server thread
            self._send(Response(500, {"error": {"code": "internal_error",
                                                "message": str(exc)}}))

    def _send(self, resp):
        payload = json.dumps(resp.payload, separators=(",", ":"),
                             sort_keys=True).encode("utf-8")
        self.send_response(resp.status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        for key, value in resp.headers.items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self._dispatch()

    def do_POST(self):
        self._dispatch()

    def log_message(self, *args):
        pass


class Service(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, host, port, handlers):
        self.service_handlers = dict(handlers)
        super().__init__((host, port), _Handler)


def serve(host, port, handlers):
    """Start the loopback HTTP service and serve forever.

    handlers: dict of exact path -> callable(Request) -> Response | dict.
    """
    server = Service(host, port, handlers)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()