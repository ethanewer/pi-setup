# Item-050 (hard) — Harden an Nginx config with per-endpoint rate limits

An internal Nginx instance serves two routes on `http://127.0.0.1:8000`:
`GET /api` and `GET /auth`. The on-disk config `/etc/nginx/nginx.conf` is
**currently broken** — it will not even pass `nginx -t`. A security review asks
you to make it valid and to add **per-route rate limiting**, then prove — with
live, validated, reloaded, and tested against normal AND throttled requests —
that everything behaves.

## Environment

- Nginx is installed. The sole config file is `/etc/nginx/nginx.conf` (a broken
  skeleton is present).
- Routes: `location = /api` returns `200 ok`; `location = /auth` returns
  `200 ok`.
- Access log output goes to `/var/log/nginx/api_access.log` using a custom
  `api_log` format that records `$remote_addr "$request" $status`.
- `curl` is available. Nginx is not currently running.

## What is wrong in the supplied config (fix ALL)

1. `sendfile upload` — this is invalid. The correct line is `sendfile on;`
   (missing semicolon and wrong token), and it alone fails `nginx -t`.
2. The `/api` route uses `burst=6;` with **no `nodelay`**, and its shared zone
   is `api_limit:10m` when it must be `1m`.
3. `/auth` has **no rate limit** and there is no zone for it.
4. **The routes currently use `return 200 "ok\n"`, which returns in the rewrite
   phase — that runs **before** the `limit_req` pre-access phase, so any
   configured rate limit is silently bypassed.** To actually throttle traffic,
   each route must be served by a real content handler (e.g. a small static
   file via `root`, or a `proxy_pass` upstream), not by `return`.

## Required final configuration (exact)

Inside the `http { }` block:

```
limit_req_zone $binary_remote_addr zone=api_limit:1m rate=5r/s;
limit_req_zone $binary_remote_addr zone=auth_limit:1m rate=1r/s;
limit_req_status 429;
```

Inside `location = /api`:

```
limit_req zone=api_limit burst=5 nodelay;
root /var/www/nginx;
default_type text/plain;
```

Inside `location = /auth`:

```
limit_req zone=auth_limit burst=1 nodelay;
root /var/www/nginx;
default_type text/plain;
```

Fix `sendfile on;`. Keep both `access_log /var/log/nginx/api_access.log
api_log;` lines so every request (throttled included) is logged with status.

The two routes are served from the static files `/var/www/nginx/api` and
`/var/www/nginx/auth` (each containing the plain text `ok`), so an under-limit
request gets HTTP 200 from a content handler that runs AFTER the rate limiter,
and an over-limit burst is throttled to HTTP 429.

## Workflow (safety discipline)

1. Run `nginx -t` and observe the failure.
2. Edit `/etc/nginx/nginx.conf` to fix syntax + apply the required zones/limits.
3. Run `nginx -t` again; it must succeed.
4. Start with `nginx` (or reload with `nginx -s reload` if already up).
5. Verify normal traffic: `curl http://127.0.0.1:8000/api` and
   `curl http://127.0.0.1:8000/auth` each return `200`.
6. Verify throttled traffic per route:
   - burst `/api` with ~16 rapid requests — some `429`, some `200`;
   - burst `/auth` with 8 rapid requests — several `429`;
   - after a ~1.5 s pause, a single request to each route returns `200` again
     (the per-route bucket refilled).
7. Leave the service running.

## Verifier checks (independent)

- `nginx -t` passes on the agent-installed config.
- The server answers on `127.0.0.1:8000`.
- `/api`: initial = `200`; a 16-request burst has >= 3 `429` and >= 1 `200`; a
  spaced follow-up = `200`.
- `/auth`: initial = `200`; an 8-request burst has >= 3 `429`; a spaced
  follow-up = `200`.
- `/var/log/nginx/api_access.log` exists and contains log lines with both `429`
  and `200` statuses (throttled requests must be logged).

Do not change ports, server names, route paths, or the fact that an
under-limit request returns `200`.