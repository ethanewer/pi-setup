# Configure the Quiet Loom analytics Jupyter Server

The **Quiet Loom** analytics pod serves a single-node Jupyter Server on a shared
VM. Its binding, port, and authentication posture are controlled by one Jupyter
config file plus a small deployment profile that the config file reads when it
loads. Your job is to write that config file. The grader will load your file
under several deployment profiles it has never shown you, so the file must be
correct on **any** profile conforming to the contract below — do not hard-code
the profile contents you can see.

## Environment

- Working directory: `/app`.
- `/app/deploy_profile.json` already exists (visible sample). The verifier will
  replace its contents between runs; **never edit it yourself.**
- `jupyter` / `jupyter server` (Jupyter Server 2.x) and Python 3.12 are
  installed.

## Deliverable

`/app/jupyter_notebook_config.py` — a Jupyter **config file** that
`jupyter server --config=/app/jupyter_notebook_config.py` will load. It must be
a normal Python config module that defines a module-level `c = get_config()`
and sets exactly the behaviour below.

### Binding and port

- The listen **address** is the wildcard interface: `c.ServerApp.ip = "0.0.0.0"`
  and the legacy alias `c.NotebookApp.ip = "0.0.0.0"`. The probe service must
  be able to reach the server on every interface, so loopback-only binding is
  wrong.
- The listen **port** comes from the deployment profile
  `/app/deploy_profile.json` (a JSON object). Your config file must read it at
  load time:
  - If the file parses as a JSON object and its `"listen_port"` value is an
    integer (not a bool) with `1 <= listen_port <= 65535`, the port is that
    value.
  - In every other case — file missing, unparsable JSON, not an object, key
    absent, wrong type, out of range — the port falls back to the default
    **`9318`**.
  - The config file must **never crash on load** because of a bad profile.
  - Set the port on both `c.ServerApp.port` and `c.NotebookApp.port`.

### Authentication (probed by the grader)

Authentication is fully disabled for the internal probe service. On **both**
`ServerApp` and `NotebookApp`:

- `token = ""`
- `password = ""`
- `open_browser = False`

### Root

- `c.ServerApp.allow_root = True`.

## How the grader checks you

1. **File-content check:** your config file is loaded with Jupyter's own config
   loader and the resulting values are inspected: the address, the profile-
   derived port, token/password/open-browser, and allow_root. A missing or
   malformed config line fails this check outright.
2. **Live server checks (hidden profiles):** for each hidden deployment
   profile, the grader writes it to `/app/deploy_profile.json`, launches
   ```bash
   jupyter server --config=/app/jupyter_notebook_config.py --no-browser \
       --allow-root --ServerApp.root_dir=/tmp/ql
   ```
   and requires the server to end up listening on the profile's port on the
   wildcard interface (reachable on a non-loopback local address, not just
   `127.0.0.1`) and to answer `GET /api/status` with HTTP **200** without any
   token (a token-protected server answers `403`, so your config must actually
   switch auth off).

Hidden profiles include: a normal alternate port, a different alternate port,
a profile without the key, an out-of-range port, and a corrupted (unparsable)
profile. The fallback cases must end up on `9318`.

The grader launches the server itself; you do not need to start anything. Your
file must load without a traceback and let the server bind.

## Constraints

- The config file must be dependency-free apart from what a Jupyter config
  module provides (`get_config`) and the Python standard library (`json`, `os`)
  for reading the profile.
- No network access is needed at verify time beyond the local checks above.
- Do not modify `/app/deploy_profile.json`.
