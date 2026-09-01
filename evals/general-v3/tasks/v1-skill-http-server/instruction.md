Write a self-contained HTTP server in Python at **`/app/serve.py`** using only the standard library (no external packages). It must bind to `127.0.0.1:8090` and handle these routes:

- `GET /ping` → HTTP 200, body exactly `pong`
- `GET /info` → HTTP 200, body exactly `{"app":"bench"}` (single line, no trailing newline required)
- any other path → HTTP 404

A complete minimal implementation using `http.server.HTTPServer` is recommended. For example shell: the server should run indefinitely once started.

Then start your server: `python3 /app/serve.py &` — and verify both routes with curl, for example:
```
curl -s http://127.0.0.1:8090/ping
curl -s http://127.0.0.1:8090/info
```

The verifier will (re)start `/app/serve.py`, issue a GET to `/ping` and `/info`, and require the exact responses `pong` and `{"app":"bench"}`.