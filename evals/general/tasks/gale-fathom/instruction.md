# Gale Fathom — reproducible platform provisioning

Gale Fathom is a marine-survey data shop. They need a **reproducible provisioning
pipeline** that turns a fresh machine into a working survey-analysis platform. Your
job is to author the provisioning script that builds the whole platform, and to make
it **idempotent** so it repairs itself if run again from an already-built or partially
broken state.

## Deliverables (exact paths)

Create exactly these in `/app`:

1. `/app/provision.sh` — an **idempotent**, standalone `bash` script that builds the
   complete platform described below and exits `0` on success. It must do the real
   work (create the venv and conda env, install packages, bring up services, write
   the lock file). Make it executable (`chmod +x`).
2. `/app/env/.venv` — the **virtual environment** created by the script (see "venv").
3. `/app/pinned.txt` — the **lock file** created by the script (see "Lock file").

## What the platform must contain

Everything is driven by `/app/provision.sh`. The platform has these independent but
complementary parts.

### 1. A pinned Python virtual environment (`/app/env/.venv`)

Create a venv at `/app/env/.venv` from the system `python3` and install into it, from
the **offline local wheel index** `/opt/gale-index`, the pinned package:

```
fathom_core==2.4.0
```

This pulls its declared dependency `gale_math==0.6.1` automatically. After
provisioning, the venv interpreter `/app/env/.venv/bin/python` must satisfy all of:

- `import fathom_core` works and `fathom_core.__version__ == "2.4.0"`; `import gale_math`
  works and `gale_math.__version__ == "0.6.1"`. (Only the **2.4.0** wheel has the
  `gale_math` dependency; the legacy `1.3.0` wheel does not.)
- `fathom_core.depth_scale(seed, n)` returns exactly the correct deterministic list:
  - `depth_scale(7, 5) == [116, 333, 938, 571, 640]`
  - `depth_scale(3, 6) == [432, 161, 702, 495, 980, 989]`
  - `depth_scale(11, 4) == [800, 505, 174, 999]`

  These values are **version-specific** — installing the legacy `1.3.0` wheel produces
  a different (and wrong) sequence, which is how the verifier tells you the pin is
  respected.
- The console entry point `fathom-cli` is installed in the venv
  (`/app/env/.venv/bin/fathom-cli`) and is runnable:
  `fathom-cli --seed 7 --n 5` prints exactly `116 333 938 571 640`.

Use the local index only (no network):

```bash
/app/env/.venv/bin/pip install --no-index --find-links=/opt/gale-index 'fathom_core==2.4.0'
```

The wheels available in `/opt/gale-index` are `fathom_core` (`1.3.0`, `2.4.0`) and
`gale_math` (`0.6.1`).

### 2. A pinned Miniconda + a conda env with a specific Python version

The platform runs its ops tooling on **conda**. A pinned, official Miniconda
installer is already staged at `/opt/miniconda-installer.sh` (Miniconda3-py312,
conda **24.9.2**). Use it to **install Miniconda non-interactively** into
`/app/miniconda3`:

```bash
bash /opt/miniconda-installer.sh -bfp /app/miniconda3
```

Then create a conda environment named **`gale311`** whose default Python
interpreter is exactly **Python 3.11** (the system is 3.12; the conda env must be a
distinct, *specific* 3.11):

```bash
/app/miniconda3/bin/conda create -q -y -n gale311 python=3.11
```

The verifier checks all of:

- `/app/miniconda3/bin/conda --version` reports the pinned **24.9.2**.
- `conda run -n gale311 python -c '...'` reports **3.11**.
- The pinned package is installed **inside the conda env** so that
  `conda run -n gale311 python -c "import fathom_core; assert fathom_core.depth_scale(7, 5) == [116, 333, 938, 571, 640]"` passes (install it from `/opt/gale-index`
  with the env's pip).

### 3. Non-interactive git + web + SSH stack

The base image already ships `git`. Bring in the **web** and **SSH** server packages
**non-interactively** (no prompts) so `nginx` and `sshd`/`openssh-server` are
installed and usable — e.g. with `DEBIAN_FRONTEND=noninteractive` and
`apt-get install -y --no-install-recommends nginx openssh-server`. There is **no
systemd** in the container, so "usable" means:

- `nginx`, `sshd` (and `git`) are on `PATH` and actually function.
- The web server is *started* and serves a marker. Provision:

  - a config at `/app/nginx-fathom.conf` that listens on `127.0.0.1:8091` with
    document root `/var/www/fathom`;
  - `/var/www/fathom/marker.html` containing exactly `gale-fathom online`;
  - start nginx with that config (e.g. `/usr/sbin/nginx -c /app/nginx-fathom.conf`).
    The verifier will `curl http://127.0.0.1:8091/marker.html` and requires the body
    `gale-fathom online`, and checks `nginx -t -c /app/nginx-fathom.conf` validates.
- `sshd` is usable: the verifier runs `/usr/sbin/sshd -t` and requires it to validate.
  Generate any missing SSH host keys with `ssh-keygen -A`.

### 4. A self-contained `uv` project (`/app/fathom`)

Create a uv project at **`/app/fathom`** (a `pyproject.toml` plus its `uv.lock`) that
declares the pinned deps `fathom_core==2.4.0` and `gale_math==0.6.1`, resolving
**from the local index** so `uv sync` needs no network. Configure uv's
`find-links` to `/opt/gale-index`, e.g.:

```toml
[tool.uv]
find-links = ["/opt/gale-index"]
```

After provisioning, `cd /app/fathom && uv run python -c "import fathom_core; assert fathom_core.depth_scale(7, 5) == [116, 333, 938, 571, 640]; print('ok')"`
must pass (i.e. the project resolves and materialises its own environment without an
extra install step).

### 5. Login-shell auto-activation (bash **and** zsh)

Write **both** `/root/.bashrc` and `/root/.zshrc` so that any new login shell
activates conda and the `gale311` environment. Each file must contain a line
`conda activate gale311` after sourcing conda's shell hook, e.g.:

```bash
source /app/miniconda3/etc/profile.d/conda.sh
conda activate gale311
```

### 6. Lock file `/app/pinned.txt`

`/app/pinned.txt` must be the output of `pip freeze` for the **venv**
(`/app/env/.venv/bin/pip freeze`), written by your script so it reflects the versions
actually installed. The verifier checks it contains the pinned packages at the pinned
versions (`fathom_core==2.4.0`, `gale_math==0.6.1`) **and** that the venv really has
those exact versions installed.

## Robustness / edge cases (the verifier re-runs your script from many states)

`/app/provision.sh` is executed repeatedly by the verifier, from the fresh image and
again from several **pre-existing, partially-broken states**. It must succeed (exit
`0`) and leave the full platform correct from **all** of them:

1. **Fresh** — nothing provisioned yet.
2. **Stale venv / wrong pin** — `/app/env/.venv` already exists but contains the
   legacy `fathom_core==1.3.0` and `/app/pinned.txt` lists the wrong pin. Provisioning
   must upgrade the venv to `2.4.0` (and its dependency) and regenerate the lock.
   Recreating the venv with `python3 -m venv --clear /app/env/.venv` is a robust way to
   wipe any wrong/old install.
3. **Wrong conda Python** — Miniconda is installed but `gale311` exists with the wrong
   Python version (e.g. 3.10 instead of 3.11). Provisioning must detect the mismatch
   and recreate the env with the requested 3.11.
4. **Missing services** — `nginx`/`openssh-server` are purged and `marker.html` and
   `/app/nginx-fathom.conf` are gone. Provisioning must reinstall them
   non-interactively and bring the web server back up.
5. **Missing uv project / shell init** — `/app/fathom` is gone and `/root/.bashrc` /
   `/root/.zshrc` are missing. Provisioning must recreate the uv project and both
   shell init files.

The cleanest approach is to make each step **idempotent** (recreate/repair rather
than assume a pristine state) and never fail when a directory already exists or is
broken.

## Rules

- Work only in `/app` (plus the system locations required by the task: the venv, the
  Miniconda install under `/app/miniconda3`, nginx/SSH package + service state, and
  root's shell init files). Do not modify `/opt/gale-index` or
  `/opt/miniconda-installer.sh`.
- Do not hard-code or special-case the verifier: `provision.sh` must genuinely build
  and repair the platform described above.
- Network may be used for conda's channel and `apt-get`, but **every pip install must
  use only the local index** `/opt/gale-index` (`--no-index --find-links`), and the
  uv project must resolve from `/opt/gale-index` too.
- The verifier does not read your source: it only runs `/app/provision.sh` and then
  inspects the resulting platform.

When finished, make sure `/app/provision.sh` is executable and all deliverables exist
(`/app/provision.sh`, `/app/env/.venv`, `/app/pinned.txt`).
