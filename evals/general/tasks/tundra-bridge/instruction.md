# Tundra Bridge

You are provisioning a static web site for **Tundra Bridge**. A standing entry page
must be served over plain HTTP on a **non-default port** and, additionally, over
**TLS on 443**, with per-IP request rate limiting, a **named** access-log format, a
custom 404 page, working host-name resolution, and a statistics-printing self-test.

Your graded deliverable is a set of files under `/app`. The grader will re-execute
`/app/nginx.conf` into nginx, re-start the server, then probe the running service and
run the helper scripts. Nginx and `openssl`/`curl`/`python3` are already installed.

Do **not** read `/tests` or anything the harness generated. You may modify the
standard system files the task requires: the nginx config tree
(`/etc/nginx/conf.d`, `/etc/nginx/sites-enabled`, `/var/log/nginx`) and the
host-resolution files (`/etc/hosts`, `/etc/nsswitch.conf`).

## Site identity

- `server_name` / domain: **`tundra.example`** (alias `www.tundra.example`).
- Plain HTTP port: **`8080`** (non-default). Document root: **`/app/site`**.
- TLS port: **`443`**. Same document root `/app/site`.
- Access log: **`/var/log/nginx/tundra.example.access.log`** written with a **named**
  `log_format`. Every access-log line contains the literal token `tundra-log-9`.
- Per-IP rate limit on the `8080` server: a burst of rapid requests returns HTTP
  **`429`**.
- Custom 404: any missing path on `8080` returns HTTP `404` and the body of
  `/app/site/404.html`.

### Required page substrings
- `/app/site/index.html` body contains the exact token `tundra-welcome-7`.
- `/app/site/404.html` body contains the exact token `tundra-missing-3`.

## Deliverables (all under `/app`)

### 1. `/app/nginx.conf` — nginx server config snippet
Installed by the grader as `/etc/nginx/conf.d/tundra.example.conf`. It must provide:

- a `server` on `listen 8080;` (and optionally `[::]:8080`) with
  `root /app/site;`, `server_name tundra.example www.tundra.example;`,
  `index index.html;`.
- per-IP rate limiting on that `8080` server: a `limit_req_zone` directive plus a
  matching `limit_req zone=... burst=... nodelay;` and `limit_req_status 429;`.
- a custom 404: `error_page 404 /404.html;`, an `internal` `location` for
  `/404.html`, and `location / { try_files $uri $uri/ =404; }`.
- a `server` on `listen 443 ssl;` with `ssl_certificate
  /app/tls/tundra.example.crt;` and `ssl_certificate_key
  /app/tls/tundra.example.key;` plus the same `root /app/site;`.
- a single named `log_format` whose format-string contains `tundra-log-9`, plus
  `access_log /var/log/nginx/tundra.example.access.log <formatname>;` on the `8080`
  server (adding it to `443` is also fine).

The grader runs `nginx -t` on the installed config, so it must be syntactically valid
on its own. You choose the zone name, rate, burst and log-format name; the grader
only checks behavior (429s, log token/path, TLS, 200/404).

### 2. `/app/site/index.html`
The welcome page containing `tundra-welcome-7`.

### 3. `/app/tls/` directory
Self-signed cert/key pair for the domain, exactly:
- `/app/tls/tundra.example.crt`
- `/app/tls/tundra.example.key`

Certificate `CN` = `tundra.example` (include a `subjectAltName` covering
`tundra.example`). The cert and key must **match** (the grader compares their public
keys). No file may have mode `000`.

### 4. `/app/network_fix.sh` — executable host-resolution helper
Must handle these invocations and exit 0 on success:

- `bash /app/network_fix.sh` — default mode: ensure `/etc/hosts` and
  `/etc/nsswitch.conf` are set up so that `localhost`, `tundra.example` and
  `www.tundra.example` all resolve to `127.0.0.1` via `getent hosts`. The
  `/etc/nsswitch.conf` `hosts:` line must resolve through the `files` (i.e. be
  consulted first), so `/etc/hosts` is not bypassed.
- `bash /app/network_fix.sh register <host> <ip>` — make `<host>` resolve to
  `<ip>`, overwriting any existing line for that host.
- `bash /app/network_fix.sh apply <file>` — the file contains lines of
  whitespace-separated `<host> <ip>` pairs. Register every **valid** pair. Skip
  blank lines, lines starting with `#`, and malformed lines (not exactly two
  fields) without crashing. Duplicate hosts: last one wins.

### 5. `/app/selfcheck.py` — pass/fail + statistics reporter
A Python 3 script run as `python3 /app/selfcheck.py`. Its stdout must contain:

- Per-check lines exactly `CHK: <name>: PASS` or `CHK: <name>: FAIL` (label text
  contains no colon). At least 4 `CHK:` lines total and at least one `PASS`.
- A `MEAN: <float>` line and a `STD: <float>` line (decimal required), the mean and
  standard deviation of a numeric sample your script actually measures (e.g.
  per-check latencies).

The grader parses only `CHK:`, `MEAN:` and `STD:` tokens. Exit 0 if every check
passed, else nonzero — but a check for a temporarily-unavailable network should
report `FAIL` rather than abort the script. Actually exercise the deployment in the
checks (resolve the domain, fetch the HTTP and HTTPS homes, verify the index file,
verify the cert/key files exist and match).

## What the grader re-does

The grader copies `/app/nginx.conf` to `/etc/nginx/conf.d/tundra.example.conf`,
confirms the distro default site `/etc/nginx/sites-enabled/default` has been
deleted, runs `nginx -t`, (re)starts nginx, and then curls the live service. So your
nginx.conf must be valid on its own and leave the ports used by only this custom
server. It is fine for you to also install and start nginx yourself while
developing.

## Hidden checks (implement all)

The harness mounts read-only hidden inputs under `/tests/hidden`:

- **`log_probe.txt`** — one probe token (e.g. `probe-snow-7`). The grader
  `curl`s `http://127.0.0.1:8080/<probe>` (a 404 is fine, but it must be logged),
  then reads `/var/log/nginx/tundra.example.access.log` and asserts it contains
  both `tundra-log-9` and the probe token. Ensure the log directory exists and both
  200s and 404s are written to that exact path.
- **`status_checks.tsv`** — `path` then a tab then an expected HTTP `code`. The
  grader curls each `http://127.0.0.1:8080<path>` and requires the status to match.
  Contains a mix: `/ → 200`, a shallow missing path → `404`, and a deep missing path
  (e.g. `/a/b/c/watch`) → `404`. Your `try_files`+`error_page` must produce a 404 for
  any missing path.
- **`aliases.tsv`** — a fixture of valid, blank, `#`-commented and one malformed
  line, with a mix of tab and space separators and stray whitespace. The grader runs
  one `bash /app/network_fix.sh apply /tests/hidden/aliases.tsv`, plus a
  `register` per valid host, and asserts `getent hosts <host>` reports the intended
  IP for each valid host. The script must skip malformed/blank/comment lines and
  register every valid mapping.

## Notes

- All deliverables are real regular files under `/app` (no symlinks). `network_fix.sh`
  must be executable. No file mode `000`.
- The service must genuinely be up: the grader itself curls
  `http://127.0.0.1:8080/` and `https://127.0.0.1:443/`.
- Fresh container; only `nginx`, `openssl`, `curl`, `python3`. No internet DNS is
  available, so `tundra.example` resolves only through `/etc/hosts` after your
  `network_fix.sh` runs.