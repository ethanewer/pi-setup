# forecastle-current: upstream-clone bugfix task on encode/httpx.
#
# The image ships the BUGGY tree — the parent of the upstream fix that closed
# the issue — as /app/src, editable-installed, so the agent gets the real tree
# with the real bug still in it. A pristine pre-fix reference interpreter
# lives at /opt/parent-venv/bin/python (root-owned, non-editable install from
# a throwaway clone, source deleted afterwards); the verifier uses it to run
# the agent's reproduction against the pre-fix code and requires the bug to
# show there.
#
# Network exists at build time only; the trial has none.

FROM bench-base:python-3.12

ARG UPSTREAM_SHA=df5345140e09ac6c2de0d9589bcd6f3e31c6aa3f
ARG FIX_SHA=6d852d319acd5d97caf14037dff15ede04b37542

# git safety for uid-1000 trials and a build identity (agents may git-commit).
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Pinned test toolchain, resolved against this base image's Python 3.12.
RUN pip install --no-cache-dir pytest==8.4.1 anyio==4.9.0 trio==0.31.0 uvicorn==0.35.0 trustme==1.2.0 cryptography==45.0.4 chardet==5.2.0 h2==4.2.0 brotli==1.2.0 socksio==1.0.0

# The agent's tree: init + fetch ONLY the parent (buggy) commit, then detach
# onto it. A plain `git clone --depth 1 <url>` would ALSO pull the current
# main-tip into the pack, and that tip's tree contains the fixed code -- the
# agent could `git cat-file -p origin/master:httpx/_client.py` and read the
# answer with no network at all (this was verified before repair: the tip
# object b5addb64 was present and its _client.py had all three _set_timeout
# hits). Fetching a single SHA brings none of that. Fail closed against pin
# drift, a leaking historical object, and ownership: the tree is chowned to
# uid 1000 inside the same layer that created it.
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/encode/httpx.git \
 && git fetch --quiet --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout --quiet FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git rev-list HEAD --count)" = 1 \
 && chown -R 1000:1000 /app/src

# Extract the project's own regression test for the bug from the FIX commit
# through a SEPARATE throwaway clone under /tmp, removed afterwards, so the
# fix object never enters the repository the agent receives (the agent could
# otherwise read the answer with `git log --all` and no network at all).
RUN git clone --depth 1 https://github.com/encode/httpx.git /tmp/golden-clone \
 && cd /tmp/golden-clone \
 && git fetch --quiet --depth 1 origin ${FIX_SHA} \
 && git checkout --quiet ${FIX_SHA} -- tests/test_timeouts.py \
 && install -o 1000 -g 1000 -m 0644 tests/test_timeouts.py /app/src/tests/test_timeouts.py \
 && cd / \
 && rm -rf /tmp/golden-clone \
 && cd /app/src \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# Pristine pre-fix reference interpreter: a throwaway clone of the parent
# commit, pip-installed (not editable, so it cannot drift even if some file
# under /app changed) into a root-owned venv; the source is deleted after.
RUN python3 -m venv /opt/parent-venv \
 && git clone --depth 1 https://github.com/encode/httpx.git /opt/src-parent-clean \
 && cd /opt/src-parent-clean \
 && git fetch --quiet --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout --quiet ${UPSTREAM_SHA} \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && /opt/parent-venv/bin/pip install --no-cache-dir /opt/src-parent-clean \
 && cd / \
 && rm -rf /opt/src-parent-clean

# Editable install: changes the agent makes under /app/src are live.
RUN cd /app/src \
 && pip install --no-cache-dir -e . \
 && python3 -c "import httpx; assert httpx.__version__ == '0.27.0'; print('httpx', httpx.__version__, 'editable at /app/src')" \
 && /opt/parent-venv/bin/python -c "import httpx; print('venv httpx', httpx.__version__, httpx.__file__)"

# Build gate A: the non-golden suite is green on the pristine buggy tree.
# (test_write_timeout is excluded: it trips an upstream GC/ResourceWarning
# flake on the trio backend in this environment, unrelated to the bug; the
# connect test is network-marked by the project and would need egress.)
RUN cd /app/src \
 && python3 -m pytest tests/client/test_client.py tests/client/test_async_client.py -q -p no:cacheprovider -m "not network" -rf 2>&1 | tail -4 \
 && python3 -m pytest tests/test_timeouts.py -q -p no:cacheprovider -m "not network" -k "read_timeout or pool_timeout" -rf 2>&1 | tail -4

# Build gate B: the freshly extracted golden regression test must FAIL on the
# buggy tree (both anyio backends), proving it targets the bug.
RUN python3 - <<'PY'
import subprocess, sys

r = subprocess.run(
    [sys.executable, "-m", "pytest", "tests/test_timeouts.py", "-q",
     "-p", "no:cacheprovider", "-m", "not network", "-k", "new_request_send_timeout"],
    cwd="/app/src", capture_output=True, text=True,
)
out = (r.stdout or "") + (r.stderr or "")
print(out[-1600:])
assert r.returncode != 0, "golden test unexpectedly PASSED on the buggy tree"
assert "2 failed" in out, "expected 2 failed (one per anyio backend)"
assert "DID NOT RAISE" in out, "failure must be the missing TimeoutException"
print("GOLDEN FAILS AT PARENT (expected), both anyio backends")
PY

# Build gate C: the reference interpreter reproduces the bug (client timeout
# ignored -> send succeeds).
RUN /opt/parent-venv/bin/python - <<'PY'
import http.server, socketserver, threading, time, httpx
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(0.25)
        self.send_response(200); self.send_header('Content-Length','2'); self.end_headers(); self.wfile.write(b'ok')
    def log_message(self,*a): pass
srv = socketserver.TCPServer(('127.0.0.1',0), H); threading.Thread(target=srv.serve_forever, daemon=True).start()
c = httpx.Client(timeout=0.05); t0=time.time()
try:
    r = c.send(httpx.Request('GET', f'http://127.0.0.1:{srv.server_address[1]}/'))
    print('SENT OK status=%s elapsed=%.3f' % (r.status_code, time.time()-t0))
    print('PRE-FIX REFERENCE REPRODUCES THE BUG')
except httpx.TimeoutException as e:
    print('TIMEOUT raised: %s after %.3f' % (type(e).__name__, time.time()-t0))
    raise SystemExit(1)  # bug absent in the reference: build fails
PY

# Thread-pool pins for the single-CPU sweep (pure-Python task; keeps any
# extension library single-threaded). No bytecode caches keep the verifier's
# site-packages manifest stable.
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 PYTHONDONTWRITEBYTECODE=1

# Manifest of the immutable parts, computed at build end. The verifier
# recomputes and rejects any drift: this protects the shipped regression
# test, the conftest fixtures (weakening the slow server could otherwise
# fake the golden test) and site-packages (a sitecustomize/.pth shim could
# otherwise fake the whole behaviour without touching the library source).
RUN python3 - <<'PY'
import hashlib, json, os

def walk(root, exclude_dirs=("__pycache__",), exclude_rel=()):
    out = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in exclude_dirs]
        for fn in sorted(filenames):
            p = os.path.join(dirpath, fn)
            if p.endswith(".pyc"):
                continue
            rel = os.path.relpath(p, root)
            if rel in exclude_rel:
                continue
            out[rel] = hashlib.sha256(open(p, "rb").read()).hexdigest()
    return out

# src_tree hashes every file under /app/src EXCEPT the one file the agent is
# supposed to change (httpx/_client.py). Without it, an agent can just ADD
# /app/src/conftest.py (or sitecustomize.py, or a pytest.ini edit) and skip
# or rewrite the shipped tests -- verified before repair that a one-file
# conftest hook makes the golden test "SKIPPED" and exit 0, defeating the
# verifier while the library stays untouched.
manifest = {
    "tests_tree": walk("/app/src/tests"),
    "site_packages": walk("/usr/local/lib/python3.12/site-packages"),
    "src_tree": walk(
        "/app/src",
        exclude_dirs=("__pycache__", ".git", ".pytest_cache"),
        exclude_rel={"httpx/_client.py"},
    ),
}
json.dump(manifest, open("/opt/forecastle-manifest.json", "w"), sort_keys=True)
print("manifest:", len(manifest["tests_tree"]), "test files,",
      len(manifest["site_packages"]), "site files,",
      len(manifest["src_tree"]), "src files")
PY

WORKDIR /app
COPY files/ /app/
# The deliverable (a NEW file the agent must create at /app/reproduce.py)
# requires /app itself writable, and the whole clone incl. .git must be
# writable by the trial user (uid 1000). The clone was chowned inline above;
# this restores ownership for anything the later build steps touched.
RUN chown 1000:1000 /app \
 && chown -R 1000:1000 /app/src