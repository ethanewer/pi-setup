# Harborlight CI notebook runner config

You maintain the **Harborlight Data Lab** CI fleet. Each runner machine starts a
headless Jupyter Server whose listening port is stamped into a small deploy
descriptor by the fleet controller. Your job is to write the single
configuration artifact that makes every runner behave identically.

## Environment

- Working directory: `/app`. Python 3.12 and the `notebook` package (providing
  the `jupyter server` CLI) are installed. The deploy descriptor
  `/app/nb_deploy.json` already exists with the shape
  `{"port": <integer>}`.
- Do not modify `/app/nb_deploy.json` — the grader rotates (and sometimes
  removes) it, so your config must read it at load time, never bake in its
  current contents.

## Deliverable (required)

`/app/notebook_server_config.py` — a Jupyter **Server config file** that the
grader loads with:

```bash
jupyter server --config=/app/notebook_server_config.py --no-browser --allow-root
```

It must be a normal Python config module: define a module-level
`c = get_config()` and set the options below. It must load without a Python
traceback, use only the standard library, and contain **no networking calls**.

## Contract

**Port resolution.** Read `/app/nb_deploy.json` when the config is loaded:

1. If the file is missing, unreadable, or not valid JSON, use the default
   port **7741**.
2. If it parses to a JSON object, take its `"port"` value:
   - The port is **valid** iff `int(value)` succeeds (an integer such as
     `8841`, or a decimal string such as `"9237"`, both count) **and** the
     resulting integer is in `1024..65535` inclusive.
   - If the value is invalid for any reason (non-numeric string, missing key,
     port below 1024, port above 65535, wrong JSON type), fall back to the
     default **7741**.

Set the resolved port on **both** `c.ServerApp.port` and `c.NotebookApp.port`.

**Listen address.** The server must bind loopback only:
`c.ServerApp.ip = "127.0.0.1"` and the legacy alias
`c.NotebookApp.ip = "127.0.0.1"`.

**No port drifting.** Set `c.ServerApp.port_retries = 0` (and
`c.NotebookApp.port_retries = 0`): if the configured port is taken the server
must fail instead of silently hopping to another port.

**Browser and auth.** Set `open_browser = False` on both `ServerApp` and
`NotebookApp`. Authentication must be disabled for the CI probe client:
`token = ""` and `password = ""` on **both** `ServerApp` and `NotebookApp`.
(A token-protected Jupyter Server answers `403` on `/api/status`, so the
empty token/password settings must actually be effective.)

## How the grader probes it

The grader rotates `/app/nb_deploy.json` between cases, launches the server
itself with your config, and requires that the server ends up listening on
`tcp://127.0.0.1:<expected port>` and answers `GET /api/status` with HTTP
`200` (tokenless). Hidden cases include at least:

| `/app/nb_deploy.json`      | expected port          |
|----------------------------|------------------------|
| `{"port": 8841}`           | `8841`                 |
| `{"port": "9237"}`         | `9237` (decimal string is valid) |
| `{}` (no `port` key)       | `7741` (default)       |
| `{"port": "seventy-seven"}`| `7741` (non-numeric)   |
| `{"port": 80}`             | `7741` (below 1024)    |
| `{"port": 99999}`          | `7741` (above 65535)   |
| file absent entirely       | `7741`                 |

Additional file-content requirements checked before launch:

- The file is syntactically valid Python (it is `exec`'d by the config loader).
- It contains a `port_retries` assignment (no silent port hopping).
- It configures both `ServerApp` and `NotebookApp`.

Notes:

- The grader launches and stops the server itself; your file only needs to
  load cleanly and make the server bind the right loopback port with auth
  disabled. If your config crashes on load or ignores the descriptor, the
  case fails.
- Keep the file dependency-free (standard library only) and defensive: a
  malformed descriptor must never crash the config load.
- Do not try to read `/tests` (unavailable to you); solve purely from this
  contract.
