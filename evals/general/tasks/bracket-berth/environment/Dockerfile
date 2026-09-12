# bracket-berth: fix a real zstd empty-body decoding bug in an upstream clone.
#
# Bakes in a shallow, SHA-pinned clone of encode/httpx at the BUGGY parent
# revision (189fc4b, the commit immediately before upstream's fix 47f4a96)
# with an editable install, so the agent gets the real repository with the
# real bug still present and any edit under /app/src is live in `import httpx`.
#
# The upstream regression test that the fix commit added is extracted to
# /opt/golden/test_decoders.py at build time. Extraction happens in a
# throwaway clone which is deleted before the trial, so the fix commit is
# NEVER reachable from the agent's checkout (the verifier asserts this).
#
# Both directions are re-confirmed inside this image at build time:
#   parent: the repro raises httpx.DecodingError ("Zstandard data is
#           incomplete") and golden test_zstd_empty fails;
#   fix:    the repro prints b'' and the whole golden file passes
#           (this check runs in the throwaway clone; /app/src ships the bug).

FROM bench-base:python-3.12

# Buggy revision and its upstream fix, both from https://github.com/encode/httpx
ARG UPSTREAM_SHA=189fc4bcbe5f314128775dec66a616ac9a31ad48
ARG FIX_SHA=47f4a96ffaaaa07dca1614409549b5d7a6e7af49

# git-uid-1000 safety and a build identity (agents may want to git commands).
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "build"

# Pinned test toolchain, resolved against this base image's own interpreter.
# zstandard MUST be present: without it httpx silently falls back to an
# identity decoder for Content-Encoding: zstd and the bug does not reproduce.
RUN pip install --no-cache-dir pytest==8.4.1 pytest-asyncio==0.26.0 anyio==4.9.0 trio==0.31.0 \
        uvicorn==0.35.0 trustme==1.2.0 cryptography==45.0.4 chardet==5.2.0 \
        h2==4.2.0 brotli==1.2.0 zstandard==0.25.0

# --- Extract the golden regression test from the FIX commit (throwaway) ----
# The fix commit enters a disposable clone that is removed immediately; it
# never lands inside /app/src/.git.
RUN git init /tmp/golden-src \
    && cd /tmp/golden-src \
    && git remote add origin https://github.com/encode/httpx.git \
    && git fetch --depth 1 origin "$FIX_SHA" \
    && mkdir -p /opt/golden \
    && git show "$FIX_SHA:tests/test_decoders.py" > /opt/golden/test_decoders.py \
    && cd / \
    && rm -rf /tmp/golden-src \
    && test -s /opt/golden/test_decoders.py

# --- Fix-direction self check (throwaway clone: parent + upstream fix) -----
RUN git init /tmp/fixchk \
    && cd /tmp/fixchk \
    && git remote add origin https://github.com/encode/httpx.git \
    && git fetch --depth 1 origin "$UPSTREAM_SHA" \
    && git checkout --detach FETCH_HEAD >/dev/null 2>&1 \
    && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
    && python3 -m pip install --no-cache-dir -e . -q \
    && git fetch --depth 1 origin "$FIX_SHA" \
    && git checkout "$FIX_SHA" -- httpx/_decoders.py \
    && python3 - <<'PY'
import subprocess
import sys

import httpx

out = httpx.Response(200, headers=[(b"Content-Encoding", b"zstd")], content=b"").content
assert out == b"", f"expected b'', got {out!r}"
res = subprocess.run(
    [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider",
     "/opt/golden/test_decoders.py"],
    capture_output=True,
    text=True,
)
if res.returncode != 0:
    print((res.stdout or "") + (res.stderr or ""))
    raise SystemExit("golden file did not pass at the fix revision")
print("fix-direction: repro prints b'' and golden test file passed")
PY

# Remove the throwaway clone and its editable install.
RUN python3 -m pip --no-cache-dir uninstall -y httpx >/dev/null \
    && rm -rf /tmp/fixchk

# --- The agent's clone: the buggy parent revision, shallow and pinned -------
RUN git init /app/src \
    && cd /app/src \
    && git remote add origin https://github.com/encode/httpx.git \
    && git fetch --depth 1 origin "$UPSTREAM_SHA" \
    && git checkout --detach FETCH_HEAD >/dev/null 2>&1 \
    && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
    && ! git cat-file -e "$FIX_SHA^{commit}" \
    && python3 -m pip install --no-cache-dir -e . -q

# --- Parent-direction self check on the pristine buggy tree ----------------
# This must FAIL: it proves the bug and the environment trap are both live in
# the exact image the agent will work in.
RUN cd /app/src && python3 - <<'PY'
import subprocess
import sys

import httpx

try:
    httpx.Response(200, headers=[(b"Content-Encoding", b"zstd")], content=b"").content
except httpx.DecodingError as exc:
    print("parent-direction: bug present ->", exc)
else:
    raise SystemExit("BUG NOT PRESENT at parent: empty zstd body decoded cleanly")

res = subprocess.run(
    [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider",
     "/opt/golden/test_decoders.py", "-k", "zstd_empty or zstd_truncated"],
    capture_output=True,
    text=True,
)
out = (res.stdout or "") + (res.stderr or "")
if res.returncode == 0 or "test_zstd_empty" not in out:
    print(out)
    raise SystemExit("golden regression signal did not fail on the pristine buggy tree")
print("parent-direction: golden test_zstd_empty fails on the buggy tree as expected")
PY

# --- Baseline: the upstream decoder suite is green on the pristine tree ----
RUN cd /app/src \
    && python3 -m pytest -q -p no:cacheprovider tests/test_decoders.py

# --- Hardening: no bytecode cache survives the build, and the git-status
#     baseline is recorded while the tree is pristine -----------------------
# The build-time test runs above leave __pycache__ trees under /app/src
# (world-writable, and invisible to `git status` because upstream's .gitignore
# ignores them). A malicious agent could transplant a forged .pyc into such a
# cache and every trial interpreter would load it without any tracked change
# or new file appearing. Delete every cache, then record the (empty) git
# status --ignored baseline into /opt/golden. Any file the agent adds later -
# ignored, untracked, or otherwise - is then a NEW entry and the verifier's
# provenance diff fails closed.
RUN find /app/src -type d -name __pycache__ -prune -exec rm -rf {} + \
    && find /app/src -name '*.pyc' -delete \
    && cd /app/src \
    && git status --porcelain --untracked-files=all --ignored | sort > /opt/golden/git_status_baseline.txt \
    && test ! -s /opt/golden/git_status_baseline.txt \
    && test ! -d /app/src/httpx/__pycache__

WORKDIR /app

# Thread-pool pins (this is a pure-Python task; keep everything single-threaded
# as the sweep is one CPU).
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 PYTHONDONTWRITEBYTECODE=1

COPY files/ /app/

# The trial may run as uid 1000; the agent must be able to edit /app/src.
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]