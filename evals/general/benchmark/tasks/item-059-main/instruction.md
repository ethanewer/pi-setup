# Serve and Install a Python Package Locally

A small Python package lives at `/app/source/` (a `pyproject.toml` +
`demo/` package exposing `demo.__version__ == "1.0.0"` and `demo.greet()`).
The environment already has `pypiserver`, `build`, `setuptools`, and `wheel`
installed for the system Python (no venv needed for those tools).

Your job: **build the package, validate the wheel in isolation, serve it from a
local PEP 503 package index, and prove a clean environment can install it from
that index — nothing else.**

## Steps

1. **Build**: from `/app/source`, build a wheel:
   `cd /app/source && python3 -m build --wheel`
   The wheel must be produced at `/app/source/dist/demo-1.0.0-py3-none-any.whl`.

2. **Validate packaging separately from serving**: before serving, inspect the
   wheel on disk. Confirm its `.dist-info/METADATA` contains exactly
   `Name: demo`, `Version: 1.0.0`, and a `Requires-Python` line (`>=3.8`).
   (e.g. `python3 -m zipfile -l <whl>` and read the `METADATA` entry).

3. **Serve**: create the PEP 503 layout the server expects on disk and start
   `pypiserver` in the background:
   ```
   mkdir -p /app/store/demo
   cp /app/source/dist/demo-1.0.0-py3-none-any.whl /app/store/demo/
   ```
   Start `pypiserver` in the background. The installed pypiserver exposes its
   CLI as a Python module entry point, so start it with either:
   ```
   pypiserver --server wsgiref --port 8080 /app/store > /app/pypi.log 2>&1 &
   ```
   (if a `pypiserver` command exists on your PATH) or, equivalently:
   ```
   python3 -m pypiserver run -p 8080 /app/store > /app/pypi.log 2>&1 &
   ```
   Wait until the service is reachable (poll
   `curl -fsS http://127.0.0.1:8080/simple/` until it succeeds).

4. **Check service reachability and versions**: fetch
   `http://127.0.0.1:8080/simple/demo/` (the PEP 503 project page). It must
   list release `1.0.0`. Record the HTTP status code you got from this fetch.

5. **Test install from a clean environment**: create a brand-new virtualenv
   (do NOT install into system Python):
   ```
   python3 -m venv /app/clean
   /app/clean/bin/pip install --index-url http://127.0.0.1:8080/simple/ \
       --trusted-host 127.0.0.1 demo
   ```
   Then verify with the clean python:
   ```
   /app/clean/bin/python3 -c "import demo; print(demo.__version__, demo.greet('agent'))"
   ```
   It must print `1.0.0 Hello, agent!`.

6. **Write the evidence file** `/app/results.json` with exactly these keys
   (values from what you actually observed):
   ```json
   {
     "wheel_path": "/app/source/dist/demo-1.0.0-py3-none-any.whl",
     "wheel_metadata_version": "1.0.0",
     "index_base_status": 200,
     "project_page_status": 200,
     "project_page_listed_versions": ["1.0.0"],
     "clean_install_version": "1.0.0",
     "clean_install_greeting": "Hello, agent!"
   }
   ```
   You may add extra keys, but these exact keys must be present with
   truthful values.

## Constraints

- Do not modify the package source under `/app/source/demo/`.
- Do not install `demo` into the system Python.
- Leave the `pypiserver` process running in the background when you finish;
  the verifier will probe it.
- Target layout is fixed: wheel at `/app/source/dist/`, served copy at
  `/app/store/demo/`, clean venv at `/app/clean/`, evidence at
  `/app/results.json`.

## Success criteria

The verifier will check: the wheel exists with correct METADATA; the served
copy exists under `/app/store/demo/`; `/app/clean` contains a working install
whose `demo.__version__` is `1.0.0` and whose `greet` matches; `/app/results.json`
is present and internally consistent; and (if the server is still up) the PEP
503 page at `http://127.0.0.1:8080/simple/` is reachable.