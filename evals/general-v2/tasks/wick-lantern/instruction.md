# Wick Lantern lightroom notebook server

The **Wick Lantern Labs** imaging team shares one Jupyter "lightroom" notebook
on the lab subnet. It must be reachable from teammates' machines (so it may
**not** listen on loopback only), take its listen port from the environment,
and ship with authentication disabled so lab tooling can probe it without a
token.

You must produce exactly one self-contained artifact, which the grader will
later run against scenarios it has never shown you.

## Deliverable

| Path | What it is |
|------|------------|
| `/app/jupyter_config.py` | A Jupyter **Server config file** that `jupyter server --config=/app/jupyter_config.py` will load and that dictates binding, port, and authentication. |

## Required config file contents

The file is a normal Python config module executed by the Jupyter config
loader. It must define a module-level `c = get_config()` and set, **for both
the `ServerApp` and the legacy `NotebookApp` aliases**:

- Listen on **all interfaces**:
  - `c.ServerApp.ip = "0.0.0.0"` and `c.NotebookApp.ip = "0.0.0.0"`.
- Allow the non-loopback bind (suppresses the remote-access confirmation):
  - `c.ServerApp.allow_remote_access = True` and
    `c.NotebookApp.allow_remote_access = True`.
- The listen **port**, taken from the environment variable **`LANTERN_PORT`**:
  - if `LANTERN_PORT` is an integer between 1 and 65535 (inclusive), the port
    equals it;
  - if it is unset, empty, **not an integer**, or out of that range, the port
    is the default **`7412`**.
  - Set both `c.ServerApp.port` and `c.NotebookApp.port`.
- `open_browser` is `False` for both `ServerApp` and `NotebookApp`.
- Authentication is **disabled**: `token == ""` and `password == ""` on both
  `ServerApp` and `NotebookApp`.

Use only the Python standard library in the file (e.g. `os` for the
environment); it must load without a Python traceback.

## How the grader probes it

The grader launches

```
jupyter server --config=/app/jupyter_config.py --no-browser --allow-root
```

(without passing any port flag — the port must come from your config) under
several hidden scenarios, and for each one it requires that:

1. the server ends up listening on the expected port (explicit
   `LANTERN_PORT` values, the unset fallback, a non-integer value, and an
   out-of-range value are all exercised);
2. the server answers `GET /api/status` with HTTP **200** when requested with
   **no** credentials (a token-protected Jupyter Server answers 403, so your
   config must actually switch token auth off);
3. the server is reachable on the machine's **non-loopback** address (an
   `ip` of `127.0.0.1` fails this — it must be a true all-interfaces bind);
4. the config file sets every attribute listed above on both aliases, via
   plain assignment lines of the documented form.

If the server fails to load your config or binds the wrong port, that
scenario's check fails.

The verifier launches and stops the server processes itself; you do not need
to leave anything running. Do not try to read `/tests` (it is unavailable to
you); solve purely from this contract.
