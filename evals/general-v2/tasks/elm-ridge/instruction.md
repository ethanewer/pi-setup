# Ridgeline Systems — reproducible Python workspace provisioning

Ridgeline Systems needs a **reproducible Python workspace** that can be rebuilt on a
fresh image from scratch. Your job is to author the provisioning script that builds
the whole workspace and the lock file that records the pinned versions.

## Deliverables (exact paths)

Create exactly these two files in `/app`:

1. `/app/provision.sh` — an **idempotent**, standalone `bash` script that builds the
   complete workspace described below and exits `0` on success.
2. `/app/requirements.lock` — a lock file recording the actual installed pinned
   package versions in the analytics environment (see "Lock file" below).

`/app/provision.sh` must be executable (`chmod +x`) and must be safe to run from any
pre-existing `/app/venvs` state (see "Robustness" below). It must do the real work —
create venvs, install packages, generate bindings, write the config and the lock file —
it must NOT just echo pre-existing state.

## What the workspace must contain

### 1. Two named virtual environments (both Python 3.12)

Create two venvs at these exact locations using the system `python3` (3.12):

- `/app/venvs/analytics` — the analytics environment
- `/app/venvs/server` — the gRPC/chain server environment

Each must have a working `python` interpreter at `.../bin/python` reporting Python
3.12. Both venvs may inherit the preinstalled system site-packages via
`--system-site-packages` (this is how the Jupyter/grpc toolchain and the bundled old
data library become available inside them), or they may be fully isolated — your
choice, as long as the final state satisfies every check below.

### 2. Local offline pip index

All of the analytic/helper packages are pre-built wheels in the local index
`/opt/ridge-index`. Install from it with pip, e.g.:

```bash
pip install --no-index --find-links=/opt/ridge-index '<pkg>==<version>'
```

You must NOT rely on network access: only `/opt/ridge-index` and the preinstalled
system site-packages are guaranteed. The wheels in `/opt/ridge-index` are:

| package     | versions present            |
|-------------|-----------------------------|
| `ridgekit`  | `1.0.0`, `3.1.4`            |
| `ridgemath` | `0.9.2`                     |
| `sidereal`  | `0.1.0`, `0.2.1`            |
| `ridgedf`   | `1.4.0`, `2.1.0`            |
| `chain_query` | `1.0.0`                   |

### 3. Analytics environment (`/app/venvs/analytics`)

Install from `/opt/ridge-index` into the analytics venv, **pin exactly**:

- `ridgekit==3.1.4` (pulls in its dependency `ridgemath==0.9.2` automatically)
- `sidereal==0.2.1`
- `ridgedf==2.1.0`

These requirements:

- `import ridgekit` must work, `ridgekit.__version__ == "3.1.4"`, and the function
  `ridgekit.sample.score(seed, n)` must return the correct deterministic list for the
  pinned package (e.g. `score(7, 5) == [442, 525, 760, 459, 798]`).
- The console entry point `ridge-cli` must be installed and runnable:
  `ridge-cli --seed 7 --n 5` prints `442 525 760 459 798`.
- `import ridgemath` must work (installed as a dependency) with
  `ridgemath.__version__ == "0.9.2"`.
- `import sidereal` must work with `sidereal.__version__ == "0.2.1"`; the function
  `sidereal.bearing(hour, minute)` returns the correct value, e.g.
  `bearing(2, 30) == "090deg"`, `bearing(18, 7) == "105deg"`. Calling it with an
  out-of-range time (e.g. `bearing(25, 0)` or `(0, 75)`) must raise
  `ValueError`, not hang or return garbage.

**Data-library upgrade (important).** The analytics environment inherits a *bundled
old* data-frame library `ridgedf 1.4.0` from the system site-packages. In `1.4.0`,
`Table.groupby(cats)` accepts **no** `collapse=` keyword and raises
`TypeError: Table.groupby() got an unexpected keyword argument 'collapse'`. The
analytics environment must be **upgraded so `collapse=` is available**: install
`ridgedf==2.1.0` (>= 2.0.0) into the analytics venv and confirm:

- `ridgedf.__version__` starts with `"2."` (i.e. the bundled `1.4.0` is overridden).
- `Table.groupby(cats, collapse=True)` accepts the keyword and returns a dict; e.g. for
  rows `[{"region":"n","team":"a"},{"region":"n","team":"b"},{"region":"s","team":"a"}]`,
  `groupby("region", collapse=True)` returns a dict whose keys are exactly
  `["n", "s"]`.

Leaving the bundled `1.4.0` (no upgrade) will keep the `collapse=` keyword missing and
fail.

### 4. Server environment (`/app/venvs/server`)

- Install `chain_query==1.0.0` from `/opt/ridge-index` into the server venv.
  `import chain_query` must work and `chain_query.resolve(chain_id, n)` must return the
  correct value, e.g. `resolve("alpha", 3) == "417df61560d67c61"`,
  `resolve("beta", 1) == "05e3bc756e005c1b"`.
- **Generate gRPC Python bindings** from the supplied service definition
  `/app/chain.proto` into the server venv's site-packages, so that a plain
  `import chain_pb2` and `import chain_pb2_grpc` work under the server interpreter.
  The generated `chain_pb2` must define `QueryRequest` (fields `chain_id`, `n`) and
  `QueryReply` (field `hash`), and `chain_pb2_grpc` must define `ChainServiceStub`.
  Recommended:
  ```bash
  SITE="$(server-python -c 'import site; print(site.getsitepackages()[0])')"
  server-python -m grpc_tools.protoc -I /app \
      --python_out="$SITE" --grpc_python_out="$SITE" /app/chain.proto
  ```
  Do not modify `/app/chain.proto`.

### 5. Jupyter notebook server

Write a Jupyter config at `/app/jupyter_config.py` so that launching the notebook
server with the analytics interpreter on `127.0.0.1:8899` actually answers HTTP
requests. The config must set (at least) `c.ServerApp.port = 8899`,
`c.ServerApp.ip = "127.0.0.1"`, `c.ServerApp.open_browser = False`, and
`c.ServerApp.allow_root = True`. A runnable start command is:

```bash
/app/venvs/analytics/bin/python -m jupyter notebook --config=/app/jupyter_config.py --no-browser
```

### 6. Lock file `/app/requirements.lock`

`/app/requirements.lock` must be the output of `pip freeze` for the **analytics**
environment (`/app/venvs/analytics/bin/pip freeze`), written by your provision script
so that it reflects the versions actually installed. The verifier checks that the lock
file contains the pinned packages at the pinned versions (`ridgekit==3.1.4`,
`ridgemath==0.9.2`, `sidereal==0.2.1`, `ridgedf==2.1.0`) **and** that those exact
versions are what the analytics venv actually has installed.

## Robustness (edge cases the verifier probes)

`provision.sh` is re-run by the verifier from different pre-existing states of
`/app/venvs`. It must succeed (exit `0`) and produce a correct workspace from **all** of
them:

1. **Absent** — `/app/venvs` does not exist at all (fresh image).
2. **Partial** — `/app/venvs/analytics` already exists and is reasonable, but
   `/app/venvs/server` is missing and `/app/jupyter_config.py` is absent.
3. **Stale / downgraded** — `/app/venvs/analytics` already exists but contains
   out-of-date versions: `ridgekit==1.0.0`, `sidereal==0.1.0`, and (bundled) `ridgedf
   1.4.0`; the server venv and jupyter config may also be missing. Provisioning must
   bring everything up to the pinned versions.
4. **Corrupt** — `/app/venvs/analytics/bin/python` exists but is a plain text file (not
   a working interpreter) and the rest of that venv is broken; the server venv is
   missing.

A robust approach is to (re)create each venv with `python3 -m venv --system-site-packages
--clear <path>` on every run (this wipes and rebuilds it, handling every state above),
then install the pinned packages and generate the bindings. Whatever approach you use,
the final workspace must satisfy all checks regardless of the starting state, and the
script must not fail or refuse when directories already exist or are broken.

## Rules

- Work only in `/app`. Do not modify `/app/chain.proto`.
- You may create `/app` scratch directories, but the final deliverables are exactly
  `/app/provision.sh` and `/app/requirements.lock`.
- Do not rely on the network. `pip` may only use `/opt/ridge-index` (plus the
  preinstalled system site-packages).
- Do not write a solution that special-cases the verifier: `provision.sh` must genuinely
  build the workspace from scratch.

When finished, make sure `/app/provision.sh` is executable and both deliverables exist.
