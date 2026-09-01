# Item-034 (medium) — Bring up the Windows 3.11 remote-desktop VNC stack

You are standing up a **multi-process remote-desktop stack** for a "Windows for
Workgroups 3.11" guest, exposed to a browser as a noVNC page. The environment
provides a **framebuffer stand-in**: a genuine RFB/VNC-protocol server that
plays the role of the Windows 3.11 guest display. It exists so the whole VNC /
websocket / nginx pipeline can be brought up and verified without needing a real
Windows disk image. Your job is to orchestrate that pipeline, wait on **real
readiness signals** (not naive `sleep`s), and prove **keyboard input travels end
to end**.

## What is already in `/app`

- `desktop/vm.cfg` — the VM identity (`id: vm31`, `name: Windows for Workgroups
  3.11`). The guest's VNC server name is derived from this; it is `vnc-vm31`.
- `desktop/vnc_target.py` — the **guest framebuffer** (a real RFB 3.8 server).
  It listens on `VNC_HOST`/`VNC_PORT` (default `127.0.0.1:5901`) and records
  every received `KeyEvent` to `KEYS_LOG` (default `/app/keys.log`). It reads
  its identity from `desktop/vm.cfg`. Start it with
  `python3 desktop/vnc_target.py`.
- `lib/rfb_ws.py` — a WebSocket + RFB **client** helper. The useful function is
  `rfb_send_key(host, port, keysym, path="/")` which opens a WebSocket to
  `(host,port,path)`, completes the RFB no-auth handshake, and sends one
  KeyEvent for the given X11 keysym. It returns `True` on success.
- `lib/ws_bridge.py` — a minimal **websockify-style bridge**. It accepts
  WebSocket upgrades on a port (default `127.0.0.1:8080`) and, per client,
  opens a TCP connection to an RFB target (`--target 127.0.0.1:5901`) and relays
  bytes both ways. CLI:
  `python3 lib/ws_bridge.py --host 127.0.0.1 --port 8080 --path /ws --target 127.0.0.1:5901`
- `web/index.html` — the noVNC web page that a browser loads in order to drive
  the desktop; its `<input>`/keyboard path opens a WebSocket at `/ws`.

## The three tiers you must bring up (exact ports)

| tier          | service                          | address            |
|---------------|----------------------------------|--------------------|
| guest framebuf | `vnc_target.py`                 | tcp `127.0.0.1:5901` |
| websockify    | `ws_bridge.py`                  | ws `127.0.0.1:8080`, path `/ws`, tunnel→`127.0.0.1:5901` |
| web front end | **nginx** reverse proxy          | http `127.0.0.1:8081` |

1. **Guest framebuffer** — run `desktop/vnc_target.py` so it listens on
   `127.0.0.1:5901` and appends to `/app/keys.log`.
2. **websockify bridge** — run `lib/ws_bridge.py` on `127.0.0.1:8080` with path
   `/ws`, tunneling to `127.0.0.1:5901`.
3. **nginx front end** — configure and start **nginx** so that:
   - it serves `/app/web` as its document root (`index.html`) on
     `127.0.0.1:8081` (noVNC page), and
   - the location `/ws` is a WebSocket **reverse proxy** to `http://127.0.0.1:8080`
     (carry the `Upgrade` / `Connection` headers so the browser↔bridge WebSocket
     upgrade survives nginx).

Write your own `nginx.conf` (anywhere, e.g. `/app/nginx.conf`) and start nginx
with it via `nginx -c <conf> -p /tmp/t32ngx`.

## Your deliverable: `/app/up.py`

Write a single Python orchestrator **`/app/up.py`** that, when run with no args:

1. **Brings up all three tiers** if they are not already up (detect by checking
   whether that port accepts a connection; start a tier only if its port is not
   reachable). Start the guest and the bridge as child processes; start nginx
   against your config.
2. **Waits on real readiness**: for each tier, poll until the tier is genuinely
   reachable (TCP connect to the port; for nginx also require that an HTTP GET
   of `/` returns the index page). Prefer looking for a real readiness signal
   rather than fixed sleeps. Use timeouts (e.g. 45s) and fail loudly if any
   tier never becomes ready.
3. **Verifies the keyboard path end to end through the *full* stack** (through
   nginx `/ws`, i.e. the same path a noVNC browser session would use). Using
   `rfb_send_key("127.0.0.1", 8081, keysym, path="/ws")`, send these two exact
   X11 keysyms and confirm each lands in `/app/keys.log`:
   - `0x61`  (the letter `a`)
   - `0xFF0D` (the Enter key)
4. Writes `/app/report.json`:

```json
{
  "ok": true,
  "ready": {"vnc": true, "bridge": true, "nginx": true},
  "ports": {"vnc": 5901, "bridge": 8080, "nginxFrontend": 8081, "wsPath": "/ws"},
  "keys_expected": [97, 65293],
  "keys_seen": [97, 65293],
  "web_page": "Windows for Workgroups 3.11"
}
```

(Use the decimal values for the keysyms: `0x61` == `97`, `0xFF0D` == `65293`.
Customize `keys_seen` to whatever your probe actually observed, but `ok` may only
be `true` when *all* tiers are ready and **both** keys landed in `keys.log`.)

Return exit `0` iff `ok == true`.

## Requirements & notes

- Do **not** rely on timings alone: the verifier re-runs `/app/up.py` from a
  clean-ish state and checks real readiness + real keys. The services must be
  able to run after you finish (leave the tiers up, or make `up.py` lift them
  again).
- nginx must run as root in the container (`nginx -c <conf> -p <prefix>`); be
  sure the config has an `events {}` block and a listening server, and that the
  `/ws` location uses `proxy_set_header Upgrade $http_upgrade;` +
  `Connection $connection_upgrade;`.
- `/app/keys.log` is shared and append-only (one line per KeyEvent). The
  verifier independently sends additional probe keys through nginx `/ws` and
  checks they land, so do not hard-code success.
- Do not modify `vnc_target.py`, `rfb_ws.py`, or `vm.cfg`. You may add files
  (your nginx conf, helpers) but the only graded deliverable is `/app/up.py`
  plus the running stack.

The **guest framebuffer is still just an RFB server** (the Windows GUI is out of
scope); you are graded on the readiness of the three-tier stack and on the
end-to-end keyboard path.