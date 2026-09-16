# ---------------------------------------------------------------------------
# strake-offing: matplotlib/matplotlib Axes.hist timedelta-input crash
# (upstream issue #31182, fix PR #31203).
#
# The image clones matplotlib and checks out upstream PARENT commit
# 496ae85214a7029d5c8eca320cb45f013b535dfe — the revision immediately before
# commit c72236701f0371d37c8a3232133347d5b350bc59 fixed the bug — so the agent
# gets the real repository with the real bug still in it: calling the
# histogram feature with duration input (numpy timedelta64 or python
# datetime.timedelta) dies with an opaque internal numpy error instead of a
# clean explanatory TypeError.
#
# The working clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>` and detached there, so the ONLY commit object in the
# /app/src object store is the parent itself. The fix commit is never fetched
# into /app/src; the golden regression test and the fixed source file are
# extracted through a separate throwaway clone under /tmp that is deleted
# afterwards, so the fix object never enters the shipped repository.
#
# matplotlib is installed editable from /app/src (meson-python editable
# wheel: an import hook in site-packages maps the 'matplotlib' package to the
# source tree and its compiled extensions to /app/src/build/cp312). A
# pristine PRE-FIX built copy of the package is baked at /opt/prefix
# (parent-tree lib/ archive + the generated install files + the compiled
# extensions), importable in a subprocess by setting the hook-skip env var
# MESONPY_EDITABLE_SKIP and PYTHONPATH=/opt/prefix/lib. Both the /app/src tree
# and /opt/prefix are verified in-image to exhibit the bug; the golden test
# is verified in-image to FAIL on both and to PASS when the real upstream
# fixed source file is overlaid on a scratch copy.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=496ae85214a7029d5c8eca320cb45f013b535dfe
ARG FIX_SHA=c72236701f0371d37c8a3232133347d5b350bc59
ARG PIX=/app/src/build/cp312

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    MPLBACKEND=Agg \
    MPLCONFIGDIR=/tmp/mplconfig \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN mkdir -p /tmp/mplconfig && chmod 777 /tmp/mplconfig \
 && mkdir -p /logs/verifier && chmod 777 /logs/verifier

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential pkg-config ninja-build \
 && rm -rf /var/lib/apt/lists/*

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- runtime/test environment, fully pinned (the trial has no network) -----
# numpy 2.5.3 matches the mining run and reproduces the ufunc-loop crash.
# pyparsing is pinned <3.2.0 because matplotlib's pytest config turns warnings
# into errors and pyparsing 3.2.0's resetCache deprecation aborts collection.
RUN pip install --no-cache-dir \
        meson-python==0.21.1 pybind11==3.1.0 setuptools-scm==10.2.3 \
        ninja==1.13.2 meson==1.12.0 setuptools==84.0.0 wheel==0.48.0 \
        numpy==2.5.3 contourpy==1.4.0 cycler==0.12.1 kiwisolver==1.5.1 \
        fonttools==4.65.0 packaging==26.3 certifi==2026.7.22 pillow==12.3.0 \
        pytest==9.1.1 pyparsing==3.1.4

# ---- working clone: buggy parent commit only, fix commit unreachable -------
# Everything that writes into /app happens inside this one RUN so ownership
# and contents land in a single image layer (no copy-up duplication).
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/matplotlib/matplotlib.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && cd /app/src \
 && pip install --no-cache-dir --no-build-isolation -e . \
 && chown -R 1000:1000 /app/src \
 && du -sh /app/src

# ---- pristine PRE-FIX package at /opt/prefix --------------------------------
# A complete, importable copy of matplotlib exactly as built at the pinned
# parent revision: the parent tree's lib/ contents, the generated install
# files (_version.py etc. from the meson install dir), and the compiled
# extensions placed at their module-correct locations. It is what the verifier
# uses to prove the agent's reproduction actually targets the bug. Read-only.
RUN mkdir -p /opt/prefix/lib \
 && git -C /app/src archive ${UPSTREAM_SHA} lib | tar -x -C /opt/prefix \
 && cp -a ${PIX}/lib/matplotlib/. /opt/prefix/lib/matplotlib/ \
 && for f in ${PIX}/src/*.so; do \
      base=$(basename "$f"); \
      case "$base" in \
        _backend_agg*|_tkagg*) dst=/opt/prefix/lib/matplotlib/backends/$base ;; \
        *) dst=/opt/prefix/lib/matplotlib/$base ;; \
      esac; \
      cp -a "$f" "$dst"; \
    done \
 && chmod -R a+rX /opt/prefix \
 && test -f /opt/prefix/lib/matplotlib/_version.py \
 && test -f /opt/prefix/lib/matplotlib/axes/_axes.py \
 && test -f /opt/prefix/lib/matplotlib/backends/_backend_agg.cpython-312-x86_64-linux-gnu.so

# ---- fail-closed: both directions confirmed inside THIS image --------------
# (1) the installed tree (/app/src, parent) and the pristine pre-fix package
#     (/opt/prefix) must BOTH crash opaquely on timedelta input; (2) the
#     project's own regression test must FAIL on both; (3) the REAL upstream
#     fixed _axes.py, taken from a throwaway clone of the fix commit (deleted
#     immediately afterwards), must make the regression test PASS.
# The same throwaway clone supplies the golden test files; they are
# sha256-pinned into /opt/pins. site-packages is snapshot-pinned as well so
# the verifier can detect any injected file (e.g. a sitecustomize monkeypatch).
RUN python3 - <<'PYEOF'
import ast
import datetime
import hashlib
import os
import shutil
import subprocess
import sys

PARENT = "496ae85214a7029d5c8eca320cb45f013b535dfe"
FIX = "c72236701f0371d37c8a3232133347d5b350bc59"
PIX = "/app/src/build/cp312"
CLEAN = "does not currently support timedelta inputs"


def run(cmd, **kw):
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True, **kw)
    return res


def raises_opaque(tree_env, code):
    """Run `code` under tree_env; return (raised, message)."""
    full = (
        "import matplotlib\n"
        "matplotlib.use('Agg')\n"
        "import matplotlib.pyplot as plt\n"
        "import numpy as np, datetime\n"
        "fig, ax = plt.subplots()\n"
        "try:\n"
        "    ax.hist(%s)\n"
        "    print('NOERROR')\n"
        "except Exception as e:\n"
        "    print(type(e).__name__ + ': ' + str(e))\n" % code
    )
    res = run("MESONPY_EDITABLE_SKIP=%s PYTHONPATH=%s python3 -c %r" % (
        PIX, tree_env, full))
    out = res.stdout.strip()
    if out.startswith("NOERROR"):
        return False, out
    if out.startswith("TypeError") or out.startswith("UFuncTypeError"):
        return True, out
    return True, out


env_pre = "/opt/prefix/lib"

# --- direction 1: the bug must reproduce in THIS image with THESE pins -----
for code in ("np.array([1, 2, 5, 7], dtype='timedelta64[D]')",
             "[datetime.timedelta(seconds=i) for i in range(5)]"):
    ok, msg = raises_opaque(env_pre, code)
    print("prefix  %-60s raised=%s : %s" % (code[:58], ok, msg[:90]))
    assert ok, "pre-fix concept /opt/prefix did not fail on timedelta input"
    assert CLEAN not in msg, "pre-fix concept /opt/prefix shows the FIXED message"
    # installed tree (loader) must fail the same way
    res = run("cd /app/src && python3 -c %r" % (
        "import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt; "
        "import numpy as np, datetime; fig, ax = plt.subplots(); "
        "ax.hist(%s)" % code))
    assert res.returncode != 0, "installed tree did not fail on timedelta input"
    assert CLEAN not in res.stderr + res.stdout, "installed tree shows the FIXED message"

# --- golden extraction from a THROWAWAY clone of the fix commit -------------
rc = run("rm -rf /tmp/fixsrc && git clone --depth 1 --no-checkout "
         "https://github.com/matplotlib/matplotlib.git /tmp/fixsrc && "
         "cd /tmp/fixsrc && git fetch --depth 1 origin %s" % FIX)
assert rc.returncode == 0, "throwaway fix clone failed"
os.makedirs("/opt/golden", exist_ok=True)
rc = run("cd /tmp/fixsrc && git show %s:lib/matplotlib/tests/test_axes.py "
         "> /opt/golden/test_axes_fixed.py" % FIX)
assert rc.returncode == 0 and os.path.getsize("/opt/golden/test_axes_fixed.py") > 0

src = open("/opt/golden/test_axes_fixed.py", encoding="utf-8").read()
tree = ast.parse(src)
func = None
for node in ast.walk(tree):
    if isinstance(node, ast.FunctionDef) and node.name == "test_hist_timedelta_raises":
        func = node
        break
assert func is not None, "golden regression test not found in fixed test_axes.py"
body = ast.get_source_segment(src, func)
assert CLEAN in body, "golden test body does not match the expected contract"
standalone = (
    "# Golden regression test for the Axes.hist timedelta-input crash, "
    "extracted verbatim\n"
    "# from the upstream fix commit's own test_axes.py at image build time.\n"
    "import datetime\n"
    "import pytest\n"
    "\n"
    + body + "\n"
)
with open("/opt/golden/test_hist_timedelta_raises.py", "w", encoding="utf-8") as fh:
    fh.write(standalone)
# the standalone copy must parse and its function body must be byte-identical
tree2 = ast.parse(standalone)
body2 = None
for node in ast.walk(tree2):
    if isinstance(node, ast.FunctionDef) and node.name == "test_hist_timedelta_raises":
        body2 = ast.get_source_segment(standalone, node)
        break
assert body2 == body, "standalone golden copy is not byte-identical to upstream"
print("golden test extracted: %d bytes, body byte-identical to upstream" % len(body))

# --- direction 2 (pre-fix): the golden test must FAIL on both concepts ------
def pytest_out(tree_env, extra_env):
    env = dict(os.environ)
    if tree_env:
        env["MESONPY_EDITABLE_SKIP"] = PIX
        env["PYTHONPATH"] = tree_env
    env.update(extra_env)
    res = subprocess.run(
        [sys.executable, "-m", "pytest", "/opt/golden/test_hist_timedelta_raises.py",
         "-q", "-p", "no:cacheprovider"],
        cwd="/tmp", env=env, capture_output=True, text=True)
    return res

r1 = pytest_out(None, {})
assert r1.returncode != 0, "golden test unexpectedly PASSED on the installed parent tree"
assert "AssertionError" in r1.stdout + r1.stderr or "FAILED" in r1.stdout + r1.stderr
print("golden test FAILS on installed parent tree as required")
r2 = pytest_out("/opt/prefix/lib", {})
assert r2.returncode != 0, "golden test unexpectedly PASSED on /opt/prefix"
assert "AssertionError" in r2.stdout + r2.stderr or "FAILED" in r2.stdout + r2.stderr
print("golden test FAILS on /opt/prefix as required")

# --- direction 3 (post-fix): the REAL upstream fixed _axes.py must pass -----
shutil.copytree("/opt/prefix", "/tmp/fixedchk")
rc = run("cd /tmp/fixsrc && git show %s:lib/matplotlib/axes/_axes.py "
         "> /tmp/fixedchk/lib/matplotlib/axes/_axes.py" % FIX)
assert rc.returncode == 0
r3 = pytest_out("/tmp/fixedchk/lib", {})
print("golden vs upstream-fixed scratch: rc=%s" % r3.returncode)
if r3.returncode != 0:
    print(r3.stdout[-2000:])
    print(r3.stderr[-2000:])
assert r3.returncode == 0 and "1 passed" in r3.stdout, "fixed direction did not pass"
print("BOTH DIRECTIONS CONFIRMED IN IMAGE (parent=opaque crash, upstream-fixed=clean TypeError)")

# --- trust anchors -----------------------------------------------------------
os.makedirs("/opt/pins", exist_ok=True)
rc = run("cd / && sha256sum /opt/golden/test_hist_timedelta_raises.py "
         "/opt/golden/test_axes_fixed.py "
         "/opt/prefix/lib/matplotlib/axes/_axes.py "
         "/opt/prefix/lib/matplotlib/_version.py "
         "> /opt/pins/golden.sha256")
assert rc.returncode == 0
# snapshot site-packages (closes sitecustomize/pth monkeypatch attacks);
# -print0/-0 because some setuptools file names contain spaces
rc = run("cd /usr/local/lib/python3.12/site-packages && "
         "find . -path '*/__pycache__/*' -prune -o -type f -print0 | sort -z | "
         "xargs -0 sha256sum > /opt/pins/site-packages.sha256")
assert rc.returncode == 0

shutil.rmtree("/tmp/fixsrc", ignore_errors=True)
shutil.rmtree("/tmp/fixedchk", ignore_errors=True)
# The meson-python editable loader opens its build log for writing on every
# import, and the smoke import above ran as root, so those logs came back
# root-owned and a uid-1000 trial could not import matplotlib. Restore them
# HERE, inside this same RUN, rather than in a chown of its own afterwards: a
# separate layer copies the whole build tree up again for a few KB of log files.
subprocess.run(["chown", "-R", "1000:1000", "/app/src/build/cp312/meson-logs"],
               check=True)
print("golden + pre-fix package + site-packages pinned; throwaway clones deleted")
PYEOF

# ---- belt: prove the fix commit is not reachable from the trial clone -------
RUN cd /app/src \
 && if git cat-file -e ${FIX_SHA}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && test "$(git rev-list --all --count)" = "1" \
 && git status --porcelain | grep -q . && { echo "tree not clean"; exit 1; } || true \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/*.py \
 && chmod 555 /opt/pins /opt/golden \
 && cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && echo "fix commit unreachable from trial clone; HEAD = $(git -C /app/src rev-parse HEAD)"

# (the meson-logs chown that used to live here moved into the pinned-tree RUN
# above, so it lands in the same layer as the root-owned import that made it
# necessary instead of copying the build tree into a layer of its own)

WORKDIR /app

# /app must be writable by the trial user (uid 1000): create the directory
# and chown it BEFORE any content lands there, so no overlay copy-up is
# triggered later (files copied in with COPY --chown are 1000-owned already).
RUN mkdir -p /app && chown 1000:1000 /app

COPY --chown=1000:1000 files/ /app/

CMD ["/bin/bash"]