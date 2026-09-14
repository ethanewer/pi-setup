# plimsoll-bell: upstream-clone real-issue debugging task on scipy/scipy.
#
# shape (v4.3 family): the upstream repository is cloned shallow at the PARENT
# commit of the fix for gh-25448 (the bug is present), SHA-pinned and
# fail-closed at build time, then built from source with meson and installed
# as an EDITABLE (PEP 660 "redirect") install: pure-Python edits under
# /app/src take effect immediately, compiled extensions resolve from the
# meson build dir /tmp/sci-build. The trial runs with no network.
#
# The project's own regression test for the fix (TestKSTest.test_gh25448 in
# scipy/stats/tests/test_stats.py at the FIX commit) is extracted at build
# time into /opt/golden from a THROWAWAY clone that is deleted afterwards, so
# the fix commit never enters /app/src's object store and the golden test is
# out of the agent's reach (its SHA-256 is pinned by the verifier).
#
# Reproduced failure at the parent commit (bench-base:python-3.12,
# numpy 2.2.6, built from source):
#   scipy.stats.kstest(x, "norm", args=(loc, scale))
# raises  TypeError: ndtr() takes from 1 to 2 positional arguments but 3 were
# given, because _parse_kstest_args maps the string name 'norm' to the raw
# special-function CDF special.ndtr, which cannot take location/scale
# parameters. At the fix commit the string name resolves through the full
# distribution class hierarchy (getattr(distributions, name).cdf) and the
# call compares equal to the callable-CDF reference.

FROM bench-base:python-3.12

# One CPU budget: keep any numeric/blas thread pools single-threaded, never
# write bytecode into the checked-out tree (keeps the app_src manifest stable
# and honest trial runs from recreating .pyc caches).
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    MESONPY_EDITABLE_VERBOSE=1

# Build toolchain for scipy from source (numpy/cython/pythran need a full
# C/C++/Fortran toolchain; OpenBLAS comes from Debian).
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gcc g++ gfortran pkg-config libopenblas0-pthread libblas3 liblapack3 \
 && rm -rf /var/lib/apt/lists/*

# OpenBLAS discovery shim: scipy's meson build finds OpenBLAS via pkg-config
# (module name `openblas`). Debian's openblas-pthread ships no .pc, so write
# one that points at the pthread build directory and add a linker symlink.
RUN mkdir -p /opt/blas-pc \
 && printf 'prefix=/usr/lib/x86_64-linux-gnu/openblas-pthread\nlibdir=${prefix}\nincludedir=/usr/include/x86_64-linux-gnu\nName: openblas\nDescription: OpenBLAS shim for the scipy build\nVersion: 0.3.29\nLibs: -L${libdir} -lopenblas\nCflags: -I${includedir}\n' > /opt/blas-pc/openblas.pc \
 && ln -sf /usr/lib/x86_64-linux-gnu/libopenblas.so.0 /usr/lib/x86_64-linux-gnu/libopenblas.so \
 && echo /usr/lib/x86_64-linux-gnu/openblas-pthread > /etc/ld.so.conf.d/scipy-openblas.conf \
 && ldconfig

# git uid-1000 safety, build identity, and the suite's system-wide
# safe.directory entry.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Pinned build + test toolchain, resolved against this base image's
# interpreter (Python 3.12.13). Every package is pinned so a rebuild
# produces byte-identical /usr/local (the verifier pins the interpreter and
# site-packages to a build-time manifest). scipy 2.0.0.dev0 requires at
# least numpy 2.0, cython 3.2, pybind11 2.13.2, pythran 0.18.1, meson-python
# 0.15 (pyproject.toml at the pinned commit); pytest>=8 is scipy's CI floor.
RUN pip install --no-cache-dir \
    numpy==2.2.6 \
    cython==3.2.9 \
    meson==1.12.0 \
    meson-python==0.21.1 \
    ninja==1.13.2 \
    pybind11==2.13.6 \
    pythran==0.19.0 \
    pytest==8.4.2 \
    hypothesis==6.168.0 \
    pooch==1.9.0 \
    mpmath==1.4.1 \
    pytest-timeout==2.4.0 \
    pytest-xdist==3.8.0

# Main checkout: the PARENT commit (pre-fix), shallow and pinned. Clone and
# detach onto the parent by SHA, then assert HEAD == the pin so the build
# fails closed if upstream ever moves. A single-commit repo: the fix commit
# is not in the object store and no ref points anywhere else.
ARG UPSTREAM_SHA=0f7f9b2a3121102394c36e8d97bcd3ea7d5da1a1
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/scipy/scipy.git \
 && git fetch --quiet --depth 1 origin 0f7f9b2a3121102394c36e8d97bcd3ea7d5da1a1 \
 && git checkout -q FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && test -z "$(git status --porcelain)" \
 && git remote remove origin \
 && test -z "$(git for-each-ref)"

# The meson build needs scipy's pinned subprojects. Explicit list (scipy-
# mathjax is docs-only and not built). Each submodule URL was checked against
# specs/tb21_source_repositories.json by the author; none of these is a
# repository the frozen reference touches.
RUN cd /app/src && git submodule update --init --depth 1 -- \
      subprojects/array_api_compat \
      subprojects/array_api_extra \
      subprojects/boost_math/math \
      subprojects/cobyqa \
      subprojects/highs \
      subprojects/unuran \
      subprojects/xsf

# Extract the project's own regression test from the FIX commit, in a
# throwaway clone that is deleted before the layer commits. This keeps the
# fix commit out of /app/src's object store (an agent must not be able to
# recover the patch with `git show` or `git log --all`) and keeps upstream
# bytes out of the task tree itself. The method body is sliced from the
# fix-commit test_stats.py with the ast module, and the standalone file
# imports scipy's own comparison helper (scipy._lib._array_api_no_0d.xp_
# assert_close), so the test asserts exactly what upstream's test asserts.
ARG FIX_SHA=0f0a3dd37f88ecd8c4d83a5913df56471274fefa
RUN mkdir -p /tmp/golden-src /opt/golden \
 && git clone --quiet --depth 1 https://github.com/scipy/scipy.git /tmp/golden-src \
 && cd /tmp/golden-src \
 && git fetch --quiet --depth 1 origin 0f0a3dd37f88ecd8c4d83a5913df56471274fefa \
 && git show 0f0a3dd37f88ecd8c4d83a5913df56471274fefa:scipy/stats/tests/test_stats.py > /tmp/fix-test_stats.py \
 && test -s /tmp/fix-test_stats.py \
 && python3 - <<'EXTRACT'
import ast

with open("/tmp/fix-test_stats.py", encoding="utf-8") as f:
    tree = ast.parse(f.read())

body = None
for node in ast.walk(tree):
    if isinstance(node, ast.ClassDef) and node.name == "TestKSTest":
        for item in node.body:
            if isinstance(item, ast.FunctionDef) and item.name == "test_gh25448":
                body = (item.body[0].lineno, item.body[-1].end_lineno + 1)
if body is None:
    raise SystemExit("golden method test_gh25448 not found in fix-commit test_stats.py")

with open("/tmp/fix-test_stats.py", encoding="utf-8") as f:
    all_lines = f.read().splitlines(keepends=True)
method_lines = all_lines[body[0] - 1:body[1]]

preamble = (
    "# Golden regression test for scipy gh-25448 (kstest with the null given\n"
    "# as a string distribution name together with distribution parameters).\n"
    "# Extracted at image build time from the FIX commit\n"
    "#   0f0a3dd37f88ecd8c4d83a5913df56471274fefa\n"
    "# (scipy/stats/tests/test_stats.py, TestKSTest.test_gh25448) via a\n"
    "# throwaway clone; the method body below is the upstream source,\n"
    "# re-indented to module level. The test uses scipy's own\n"
    "# xp_assert_close helper (scipy/_lib/_array_api_no_0d.py).\n"
    "import numpy as np\n"
    "from scipy import stats\n"
    "from scipy import special\n"
    "from scipy._lib._array_api_no_0d import xp_assert_close\n"
    "\n"
    "\n"
    "def test_gh25448():\n"
)
with open("/opt/golden/test_gh25448.py", "w", encoding="utf-8") as f:
    f.write(preamble)
    for ln in method_lines:
        if ln.strip():
            f.write(ln[4:] if ln.startswith("        ") else ln)
        else:
            f.write("\n")
print("wrote /opt/golden/test_gh25448.py from the fix commit")
EXTRACT

RUN test -s /opt/golden/test_gh25448.py \
 && rm -rf /tmp/golden-src /tmp/fix-test_stats.py

# Build scipy from source and install it EDITABLY (PEP 660). Pure-Python
# files (including scipy/stats/_stats_py.py) are served straight from
# /app/src, so editing them takes effect immediately with no rebuild; the
# compiled extensions resolve from the fixed meson build dir /tmp/sci-build.
# Ownership moves to uid 1000 in the SAME layer (the image-size-hygiene rule:
# never chown a big tree in its own later layer).
RUN cd /app/src \
 && PKG_CONFIG_PATH=/opt/blas-pc python3 -m pip install --no-build-isolation \
      -e . -Cbuilddir=/tmp/sci-build \
 && chown -R 1000:1000 /app/src /tmp/sci-build \
 && test -f /tmp/sci-build/meson-info/intro-install_plan.json

# Fail closed on the reproduction: at the pinned parent commit the one-sample
# KS test with the null given as the string name 'norm' plus fitted (loc,
# scale) parameters MUST raise the bug's TypeError.
RUN cd /app/src && python3 - <<'CHECK'
import numpy as np
from scipy import stats
from scipy.special import ndtr
rng = np.random.default_rng(254482544825448)
x = rng.normal(size=100)
loc, scale = stats.norm.fit(x)
ref = stats.kstest(x, lambda t: ndtr((t - loc) / scale)).statistic
try:
    res = stats.kstest(x, "norm", args=(loc, scale)).statistic
except TypeError as e:
    assert "ndtr" in str(e), e
else:
    raise SystemExit(f"BUG NOT REPRODUCED at parent: string-norm kstest ran, res={res}, ref={ref}")
print("parent commit reproducibly raises the gh-25448 TypeError")
CHECK

# Warm the project's own existing KS unit slice on the pristine parent tree
# so a broken toolchain pin fails the build, not the trial (the acceptance
# reruns the same slice after the agent's change).
RUN cd /app/src \
 && python3 -m pytest -q -o addopts= -o filterwarnings=ignore -p no:cacheprovider \
      scipy/stats/tests/test_stats.py -k "TestKSTest or TestKSOneSample"

# The editable loader runs `ninja` (no-work dry run) on every fresh import;
# with MESONPY_EDITABLE_VERBOSE=1 it uses the dry-run branch and never opens
# a log file, so the build dir needs no writes. Keep the build dir COMPLETE:
# the ninja target graph references the build-time object dirs, and deleting
# them would make ninja rebuild the project on every import. Scrub only
# bytecode (derived, not part of any ninja target) and the loader log
# remnants. Ownership already moved to uid 1000 in the build RUN layer.
RUN rm -f /tmp/sci-build/meson-logs/meson-python-build-log.txt \
 && find /usr/local/lib/python3.12 /tmp/sci-build -type d -name __pycache__ -prune -exec rm -rf {} + \
 && find /usr/local/lib/python3.12 /tmp/sci-build -type f -name '*.pyc' -delete

WORKDIR /app
COPY files/ /app/
# Only the (tiny) README and the /app directory itself need ownership at
# this point: /app/src was already chowned inside the build RUN layer, so a
# `chown -R /app` here would duplicate the whole tree in a new layer.
RUN chown 1000:1000 /app \
 && chown -R 1000:1000 /app/README.md