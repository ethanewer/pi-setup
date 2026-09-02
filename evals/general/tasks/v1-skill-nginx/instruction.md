`nginx` is already installed on this system. There is a directory `/app/www` containing the file `index.html`.

Create an nginx configuration file `/app/nginx.conf` that:

1. Defines a worker process model (`worker_processes 1;`).
2. Defines an `events { worker_connections 256; }` block.
3. Sets an absolute `pid` path under `/tmp` (e.g. `pid /tmp/nginx_probe.pid;`).
4. Defines an `http { ... }` block containing a `server { ... }` that:
   - listens on TCP port `8090`
   - uses `server_name localhost;`
   - serves static files with `root /app/www;`
   - adds a response header `X-Harbor-Task: nginx` (via `add_header`).

Because this is a standalone config, use absolute paths for any `pid`, `error_log`, and `access_log` directives so nginx does not need a prefix directory.

Then **start nginx** using your config:

```
nginx -c /app/nginx.conf
```

After starting it, verify the server responds by requesting `http://127.0.0.1:8090/` and writing the full HTTP response (status line, headers, body) to `/app/probe_result.txt` using `curl`.

Leave nginx running. The evaluator will independently check that: the config parses (`nginx -t -c /app/nginx.conf`), port 8090 serves the contents of `/app/www/index.html`, and the `X-Harbor-Task` response header is present.