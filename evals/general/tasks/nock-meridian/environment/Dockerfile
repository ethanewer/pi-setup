# nock-meridian: upstream-clone real-issue debugging task on pypa/pip.
#
# The upstream repository is cloned shallow at the PARENT commit (the bug is
# present), SHA-pinned and fail-closed at build time. The project's own
# regression test for the fix (tests/unit/test_link.py at the FIX commit) is
# extracted at build time into /opt/golden from a throwaway clone that is
# deleted afterwards, so the fix commit is never in /app/src's object store.
# The trial runs with no network; everything the task needs is baked in.
#
# Reproduced failure at the parent commit (bench-base:python-3.12):
#   Link('https://example.com/a%252Fb.whl').filename -> 'a/b.whl'
# (the URL path is percent-decoded once into _path and the basename is then
# percent-decoded a second time, so a doubly-encoded separator collapses into
# a real '/'). Verified fixed at the fix commit: 'a%2Fb.whl'.

FROM bench-base:python-3.12

# git uid-1000 safety, build identity, and the suite's system-wide
# safe.directory entry.
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "build"

# Pinned test toolchain, resolved against this base image's interpreter
# (Python 3.12.13). pytest==8.4.2 + pytest-socket==0.7.0 are a verified
# compatible pair; the others (installer, scripttest, virtualenv, werkzeug,
# and their transitive deps) are imported by pip's tests/conftest.py chain.
# EVERY package is pinned so a rebuild produces byte-identical /usr/local
# (the verifier pins the interpreter and site-packages to a build-time
# manifest).
RUN pip install --no-cache-dir \
    pytest==8.4.2 \
    pytest-socket==0.7.0 \
    installer==1.0.1 \
    scripttest==3.0 \
    virtualenv==21.7.9 \
    werkzeug==3.1.8 \
    markupsafe==3.0.3 \
    pygments==2.21.0 \
    distlib==0.4.3 \
    filelock==3.32.6 \
    iniconfig==2.3.0 \
    packaging==26.3 \
    platformdirs==4.11.8 \
    pluggy==1.6.0 \
    python-discovery==1.6.0

# Main checkout: the PARENT commit (pre-fix), shallow and pinned. Resolved by
# the author via `git ls-remote https://github.com/pypa/pip.git`; the 40-hex
# assertion makes the build fail closed if the pin ever drifts.
ARG UPSTREAM_SHA=ba52753ecf1803e5b6b5dfb2782835266a71c470
# Clone the pinned parent commit DIRECTLY (git init + fetch by SHA), so the
# modern `main` tree is never fetched and the checkout exposes exactly one
# commit: the buggy parent. Fail closed if the pin ever drifts.
RUN git init --quiet /app/src \
    && cd /app/src \
    && git remote add origin https://github.com/pypa/pip.git \
    && git fetch --quiet --depth 1 origin ba52753ecf1803e5b6b5dfb2782835266a71c470 \
    && git checkout -q FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
    && test -z "$(git status --porcelain)" \
    && test -f src/pip/_internal/models/link.py \
    && git remote remove origin \
    && test -z "$(git for-each-ref)"

# Extract the project's own regression test from the FIX commit, in a
# throwaway clone that is deleted before the layer commits. This keeps the
# fix commit out of /app/src's object store (an agent must not be able to
# recover the patch with `git show`) and keeps upstream bytes out of the
# task tree itself.
ARG FIX_SHA=10dfb6b9005484578b386f64b9f36982e3dc6679
RUN mkdir -p /tmp/golden-src /opt/golden \
    && git clone --depth 1 https://github.com/pypa/pip.git /tmp/golden-src \
    && cd /tmp/golden-src \
    && git fetch --depth 1 origin 10dfb6b9005484578b386f64b9f36982e3dc6679 \
    && git show 10dfb6b9005484578b386f64b9f36982e3dc6679:tests/unit/test_link.py > /opt/golden/test_link.py \
    && test -s /opt/golden/test_link.py \
    && cd / \
    && rm -rf /tmp/golden-src

# One CPU budget; keep any extension libs single-threaded and never write
# bytecode into the checked-out tree (keeps the app_src manifest stable and
# honest trial runs from recreating .pyc caches).
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONDONTWRITEBYTECODE=1

# Warm baseline: the project's own existing unit slice (test_link.py and the
# prepare/operations tests) must already be green on the pristine parent tree
# (it is what the acceptance also asserts after the agent's change). This
# exercises the pinned toolchain at build time so a broken pin fails the
# build, not the trial.
RUN cd /app/src \
    && PYTHONPATH=src /usr/local/bin/python3 -m pytest -q -o addopts= -p no:cacheprovider \
         tests/unit/test_link.py \
         tests/unit/test_operations_prepare.py

# Timestamp pyc caches embed the source file's extraction mtime, so a rebuild
# of the same Dockerfile at a different wall time produces different
# site-packages .pyc bytes and a manifest recorded from an earlier build can
# never match. Ship none of them: bytecode is derived from the pinned
# sources, so it is not part of the deliverable, and the verifier's usrlocal
# manifest "new file" check catches any .pyc an agent plants at trial time.
RUN find /usr/local/lib/python3.12/site-packages -type d -name __pycache__ -prune -exec rm -rf {} + \
    && find /usr/local/lib/python3.12/site-packages -type f -name '*.pyc' -delete

WORKDIR /app

COPY files/ /app/