# Multi-Version Package Index: Build Both, Serve Both, Pin Both

A Python package lives at `/app/source/` (a `pyproject.toml` +
`demo/` package). It currently declares **version 1.0.0** in two places:
`pyproject.toml` (`[project] version`) and `demo/__init__.py` (`__version__`).
`pypiserver`, `build`, `setuptools`, and `wheel` are already installed for the
system Python.

Your job: end-to-end packaging and serving for **two releases** of the same
package, with clean-environment, pinned-version installs from a local
PEP 503 index — and proof that undefined versions are rejected.

## Steps

1. **Build 1.0.0 and validate its packaging separately from serving.**
   ```
   cd /app/source && python3 -m build --wheel
   ```
   The wheel `/app/source/dist/demo-1.0.0-py3-none-any.whl` must be produced.
   Inspect it in isolation: the `.dist-info/METADATA` inside the wheel must
   contain `Name: demo`, `Version: 1.0.0`, and `Requires-Python: >=3.8`.

2. **Upgrade the package to 1.0.1 in BOTH places** — the `[project] version`
   in `pyproject.toml` and `__version__` in `demo/__init__.py` — and rebuild:
   ```
   python3 -m build --wheel
   ```
   producing `/app/source/dist/demo-1.0.1-py3-none-any.whl`. Validate its
   `METADATA` too (`Version: 1.0.1`, `Requires-Python: >=3.8`, `Name: demo`).
   Keep the 1.0.0 wheel; do not delete it.

3. **Serve both from one index.** Set up the PEP 503 layout and start
   `pypiserver` on **port 8080** over `/app/store` in the background:
   ```
   mkdir -p /app/store/demo
   cp /app/source/dist/demo-1.0.0-py3-none-any.whl /app/store/demo/
   cp /app/source/dist/demo-1.0.1-py3-none-any.whl /app/store/demo/
   pypiserver --server wsgiref --port 8080 /app/store > /app/pypi.log 2>&1 &
   ```
   Poll `curl -fsS http://127.0.0.1:8080/simple/` until it responds. Then fetch
   the project page `http://127.0.0.1:8080/simple/demo/`; both release files
   (1.0.0 and 1.0.1) must appear in it.

4. **Clean-environment installs with version pins.** Create two brand-new
   venvs and install **from the running index** (never from local files or the
   system site-packages; never into the system python):
   ```
   python3 -m venv /app/clean_100
   /app/clean_100/bin/pip install --index-url http://127.0.0.1:8080/simple/ \
       --trusted-host 127.0.0.1 "demo==1.0.0"
   python3 -m venv /app/clean_101
   /app/clean_101/bin/pip install --index-url http://127.0.0.1:8080/simple/ \
       --trusted-host 127.0.0.1 "demo==1.0.1"
   ```
   Verify each: `/app/clean_100/bin/python3 -c "import demo; print(demo.__version__)"`
   must print `1.0.0`, and `/app/clean_101/bin/python3 ...` must print `1.0.1`.

5. **Prove the index rejects unknown versions.** In `/app/clean_101`, attempt:
   `/app/clean_101/bin/pip install --index-url http://127.0.0.1:8080/simple/
   --trusted-host 127.0.0.1 "demo==9.9.9"` — it must **fail** (pip exits
   non-zero and finds no matching distribution). Record that outcome.

6. **Write the evidence file** `/app/results.json` with exactly these keys
   (truthful observed values; extra keys allowed):
   ```json
   {
     "wheels_built": ["demo-1.0.0-py3-none-any.whl", "demo-1.0.1-py3-none-any.whl"],
     "index_base_status": 200,
     "project_page_listed_versions": ["1.0.0", "1.0.1"],
     "clean_100_version": "1.0.0",
     "clean_101_version": "1.0.1",
     "install_999_failed_as_expected": true
   }
   ```

## Constraints

- Do not modify `demo/__init__.py` except for the required `__version__` bump.
- Keep both wheels on disk under `/app/source/dist/` and both served copies
  under `/app/store/demo/`.
- Leave `pypiserver` running at the end; the verifier will probe it.
- The pins in step 4 must be satisfied **via the index URL**, not by file paths
  or local cache.

## Success criteria

The verifier checks: both wheels exist with correct METADATA; both served
copies exist; `/app/clean_100` and `/app/clean_101` import `demo` with versions
`1.0.0` and `1.0.1` respectively; `/app/results.json` is present, consistent,
and records the negative-version failure; and — if the server still responds —
`/simple/demo/` lists both releases.