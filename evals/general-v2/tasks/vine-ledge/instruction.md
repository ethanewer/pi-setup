# vine-ledge — Reproducible Python workspace provisioning

You are starting from a fresh, bare Python workstation. Your job is to author a
**reproducible provisioner** that builds a chain-indexing research workspace
from nothing, and to ship the exact pinned dependency set it guarantees.

Everything you must deliver is exactly two files in `/app`:

1. `/app/provision.sh` — a bash script that provisions the workspace (see below).
2. `/app/requirements.lock` — a `name==version` pin file describing the exact
   installed versions of every package the workspace must carry.

`provision.sh` must be **idempotent**: re-running it on an already-provisioned
workspace must not error or double-launch anything. The verifier will run it
again after you have already run it once.

## The platform-pinned ML toolchain (DO NOT TOUCH)

The image ships with a preinstalled, **immutable** ML toolchain:

- `torch` (distribution version `2.13.0`; `torch.__version__` reports the
  `+cu130` build qualifier)
- `transformers` version `5.16.1`

These are pinned by the platform and must survive your provisioning **bit-for-bit
unchanged in both import name and version**. A downstream offline consumer,
`/app/offline_load.py`, loads a saved model through this exact toolchain and
exits non-zero if the versions have drifted or the save/load path is broken.
**You may not upgrade, downgrade, uninstall, or reinstall `torch` or
`transformers`.** Your provisioning must add new things without disturbing these.

## What provision.sh must accomplish

Create `/app/provision.sh` that does all of the following, in this spirit:

1. **gRPC toolchain, system-wide.** Install `grpcio`, `grpcio-tools`, and
   `protobuf` into the *system* Python (not just a venv). After it runs,
   `python3 -c "import grpc"`, `import grpc_tools`, and
   `import google.protobuf` must all succeed system-wide at these exact
   versions: `grpcio==1.83.0`, `grpcio-tools==1.83.0`, `protobuf==7.36.0`.

2. **Jupyter notebook server, system-wide.** Install the `notebook` package at
   version `7.6.2` into the *system* Python, and launch it as a **persistent
   background process** bound to `0.0.0.0` on TCP **port 8899**. It must stay
   alive after the script exits, with authentication disabled
   (`--ServerApp.token='' --ServerApp.password='' --no-browser --allow-root`).

3. **Two named venvs.** Create exactly `/app/venvs/ingest` and
   `/app/venvs/serve` using the system Python, each with a working `bin/python`.

4. **Chain-query stack in the serve venv.** The source tree of the local
   package **`chainquery`** (an auto-installable, fully offline importable
   package) is provided at `/app/pkgs/chainquery`. Install it into
   `/app/venvs/serve`, together with a web microframework (**Flask** at
   `3.1.3`) and **`requests`** at `2.34.2`. After install,
   `/app/venvs/serve/bin/python -c "import chainquery, flask, requests"`
   must succeed and `chainquery.__version__ == "1.2.0"`.

5. **requests in the ingest venv.** Install `requests==2.34.2` into
   `/app/venvs/ingest` too.

6. **A responding background HTTP API on :8123.** Write a small service
   (a Flask app) that serves the chain-query contract below, and launch it as a
   persistent background process bound to `0.0.0.0` on TCP **port 8123** under
   the serve venv's Python (so it can import `chainquery` and `flask`).

7. **Write `/app/requirements.lock`.** Emit the exact pinned set of the
   required packages, one `name==version` per line (blank lines and lines
   starting with `#` are allowed):
   `grpcio`, `grpcio-tools`, `protobuf`, `notebook`, `flask`, `requests`,
   `chainquery` (pin `1.2.0`), `torch` (pin `2.13.0`), and
   `transformers` (pin `5.16.1`). These must equal what is actually installed.

## The chain-query HTTP API contract (port 8123)

The Flask service must implement two routes that use the `chainquery` package:

- `GET /health` → HTTP 200 with JSON body `{"status": "ok"}`.

- `GET /height?hash=<VALUE>` → resolves `<VALUE>` through `chainquery.lookup`:

  - If `<VALUE>` is a **valid block hash** — i.e. after stripping surrounding
    whitespace and lower-casing it is exactly **64 hexadecimal characters** —
    return HTTP 200 with JSON:
    ```json
    {"hash": "<lowercased 64-hex>", "height": 12345, "status": "confirmed"}
    ```
    where the formulas are the contract inside `chainquery` (see the package
    source: `height = int(sha256(normalized)[:8], 16) % 100000` and
    `status = "confirmed" if int(sha256(normalized)[8:16], 16) % 2 == 0 else "pending"`).
    Do not reimplement these formulas in your service — call the package.

  - If `<VALUE>` is invalid (wrong length, empty, or contains any non-hex
    character) return HTTP **400** with JSON `{"error": "<some message>"}`.

The verifier queries this service with a visible sample and with several hidden
hashes — including valid lowercase, valid **mixed-case + whitespace-padded**,
a **bad-length** (63 hex chars) value, and a **non-hex** value. Your service
must normalize and answer all of them exactly as above. Do not hardcode any
specific hash → answer mapping.

## Constraints

- Work in the `bash` provisioner invoked how you write it; no systemd, no GPU,
  no X server. The pip index is reachable and network is available during
  provisioning.
- Do **not** modify `/app/offline_load.py`, `/app/pkgs/chainquery`, or anything
  else already in the image.
- Do **not** touch the preinstalled `torch`/`transformers` toolchain.
- `provision.sh` must be executable (`chmod +x /app/provision.sh`) and
  idempotent. Verify by running it twice in a row.
- Both daemons (Jupyter :8899, chain-query API :8123) must survive after
  `provision.sh` returns.

## Deliverables recap

- `/app/provision.sh` (executable)
- `/app/requirements.lock`

Ship both, run `provision.sh` to prove the workspace works, confirm the ports
answer and all imports/versions hold, then you are done.
