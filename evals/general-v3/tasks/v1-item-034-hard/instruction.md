# Item-034 (hard) — Supervised bring-up of the Windows-3.11 remote-desktop stack

You are building the **supervised multi-process pipeline** that exposes a
"Windows for Workgroups 3.11" guest as a browser-accessible noVNC desktop. As
with the medium skill set, a real RFB/VNC server (`/app/desktop/vnc_target.py`)
plays the role of the guest framebuffer so the VNC/websocket/nginx pipeline can
be brought up and exercised deterministically — no QEMU disk image is involved.

The hard variant is **deeper and adversarial**. You must:

1. **Author the websockify bridge yourself** (WebSocket↔RFB). It is NOT provided.
2. **Supervise the whole multi-process system** with real process supervision:
   auto-respawn on failure, a pid manifest, and a readiness latch that is only
   raised after a **real** health check (an actual RFB greeting from the target),
   not after arbitrary sleeps.
3. Prove the **keyboard path end to end**, and that the stack **survives a
   worker being killed** (supervision restarts it) and **many concurrent
   keyboard sessions** all landing successfully.

## Provided low-layer files (do not modify)

- `/app/desktop/vnc_target.py` — the guest framebuffer (RFB 3.8 server). Reads
  env `VNC_HOST`/`VNC_PORT` (default `127.0.0.1:5901`) and records every
  `KeyEvent` to `KEYS_LOG` (default `/app/keys.log`). Its server name
  (`vnc-vm31`) is derived from `/app/desktop/vm.cfg`.
- `/app/desktop/vm.cfg` — VM identity.
- `/app/lib/rfb_ws.py` — WebSocket+RFB client; `rfb_send_key(host, port, keysym,
  path="/")` opens a WS at `(host,port,path)`, completes the no-auth RFB
  handshake, sends one KeyEvent for an X11 keysym, returns `True` on success.
- `/app/web/index.html` — the noVNC landing page (document root for the web
  tier). Its keyboard path opens a WebSocket at `/ws`.

## The fixed ports (exact)

- guest framebuffer: tcp `127.0.0.1:5901`
- your websockify bridge: ws `127.0.0.1:8080`, path `/ws`, tunnel → `127.0.0.1:5901`
- nginx web front end: http `127.0.0.1:8081`, serving `/app/web`, and the
  location `/ws` is a WebSocket reverse proxy → `http://127.0.0.1:8080`
  (carry Upgrade/Connection headers).

## Deliverables (graded)

Write these, then start the stack:

- **`/app/server/bridge.py`** — your websockify bridge. Accepts WebSocket
  upgrades on `127.0.0.1:8080` (path `/ws`), opens a TCP connection to the RFB
  target, and relays bytes **both ways** with correct RFC 6455 masking
  (client frames masked→unmasked to the target; server frames unmasked→masked
  isn't needed since our client accepts unmasked). It must tolerate keys sent
  in fragments / multiple concurrent sessions. Env overrides:
  `BRIDGE_PORT` (8080), `BRIDGE_TARGET` (127.0.0.1:5901).

- **`/app/server/supervisor.py`** — the process supervisor. Commands:
  - `python3 server/supervisor.py start` (default) — spawn and **supervise** the
    three workers `vnc`, `bridge`, `web`; when any worker dies, **auto-restart**
    it; maintain `/app/runtime/pids.json` = `{"vnc": pid, "bridge": pid, "web":
    pid}` (rewrite whenever a pid changes); write `/app/runtime/ready.json`
    only when **all** of these are true: `5901`, `8080`, `8081` are reachable,
    the target answers a real RFB greeting (`RFB 003.008`), and all three
    workers are supervising.
  - `python3 server/supervisor.py stop`    — kill the supervised workers (from
    `pids.json`), run `nginx -s stop`, and exit.

  nginx config: write `/app/server/nginx.conf` and launch nginx as the `web`
  worker (`nginx -c /app/server/nginx.conf -p /tmp/t34hng`).

- Start the supervisor at least once so the stack is **up and ready when you
  finish** (leave it running; the verifier may stop and re-start it).

## Behavioral requirements (these are what the verifier checks)

- **Real readiness.** `ready.json` must only appear after a real RFB handshake
  (a target that merely listens but does not complete the greeting must not be
  "ready").
- **Supervision.** If the `vnc` worker is killed (`kill -9`), the supervisor must
  restart it with a **new pid**, update `pids.json`, and raise `ready` again
  once all ports are healthy.
- **End-to-end keys.** Through nginx `/ws` (the browser path), multiple
  concurrent `rfb_send_key` sessions must all land in `/app/keys.log`.

## Suggested sequence

1. Write `server/bridge.py`; test it alone: `rfb_send_key("127.0.0.1", 8080,
   0x61, "/ws")` and confirm `KeyEvent 97` appears in `/app/keys.log`.
2. Write `server/supervisor.py` (`start`/`stop`/`status`), then start it.
3. Wait for `ready.json`; push 24+ distinct keys through nginx `/ws` in parallel
   threads and confirm every one lands in keys.log.
4. Kill the `vnc` pid from `pids.json`; confirm the supervisor respawns it (new
   pid, port back up) and keys still land.

Final score depends on: `server/supervisor.py` starting with real (RFB-checked)
readiness, a pid manifest with all three workers, an adversarial
concurrent-key storm that all lands, and automatic restart of a killed worker
with subsequent end-to-end keys.

## Notes

- Use the X11 keysym integers directly (e.g. `0x61` = 97, `0xFF0D` = 65293).
- `/app/keys.log` is append-only, one `KeyEvent <int> down=0/1` line per event.
- Do not modify the provided `/app/desktop/*` or `/app/lib/*` files. You may add
  any files under `/app/server/`.
- Do not use naive fixed sleeps as the whole readiness story: re-check
  reachability and the RFB handshake on a loop.