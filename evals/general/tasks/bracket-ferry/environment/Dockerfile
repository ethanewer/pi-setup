# bracket-ferry: upstream-clone debugging task on pypa/pip.
#
# The upstream repository is cloned shallow at the PARENT commit (the bug is
# present), SHA-pinned and fail-closed at build time. The project's own
# regression test for the fix is extracted from the FIX commit at build time
# into /opt/golden -- from a throwaway clone that is deleted afterwards, so
# the fix commit is never in /app/src's object store. The trial runs with no
# network; everything the task needs is baked into this image.
#
# Reproduced failure at the parent commit (bench-base:python-3.12):
#   ValueError: invalid literal for int() with base 10: ''
# at src/pip/_internal/commands/show.py:192 when a distribution's metadata
# has no Metadata-Version header. Verified fixed at the fix commit.

FROM bench-base:python-3.12

# git uid-1000 safety, build identity, and the "no root ownership surprises"
# system-wide safe.directory entry required by the suite's git gate.
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "build"

# Pinned dependency toolchain, resolved against this base image's interpreter
# (Python 3.12.13). pytest==8.4.2 + pytest-socket==0.7.0 are a verified
# compatible pair: pytest 9.x breaks the pytest-socket plugin hooks. The
# others (installer, scripttest, virtualenv, werkzeug, and their transitive
# deps) are imported by pip's own tests/conftest.py chain, which every test
# under tests/ loads. EVERY package is pinned to a fixed version so a rebuild
# produces byte-identical /usr/local (the verifier pins the interpreter and
# site-packages to a build-time manifest).
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
# the author on 2026-09 via `git ls-remote https://github.com/pypa/pip.git
# b98096615dc25fb9438f87bacfa446589d34e97d`. The 40-hex assertion makes the
# build fail closed if the pin ever drifts.
ARG UPSTREAM_SHA=b98096615dc25fb9438f87bacfa446589d34e97d
RUN git clone --depth 1 https://github.com/pypa/pip.git /app/src \
    && cd /app/src \
    && git fetch --depth 1 origin b98096615dc25fb9438f87bacfa446589d34e97d \
    && git checkout -q b98096615dc25fb9438f87bacfa446589d34e97d \
    && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
    && test -z "$(git status --porcelain)" \
    && test -f src/pip/_internal/commands/show.py

# Extract the project's own regression test from the FIX commit, in a
# throwaway clone that is deleted before the layer commits. This keeps the
# fix commit out of /app/src's object store (an agent must not be able to
# recover the patch with `git show`), and keeps upstream bytes out of the
# task tree itself.
ARG FIX_SHA=4ab145f7b7e3c4e4617cbff3743fde7dff802ebd
RUN mkdir -p /tmp/golden-src /opt/golden \
    && git clone --depth 1 https://github.com/pypa/pip.git /tmp/golden-src \
    && cd /tmp/golden-src \
    && git fetch --depth 1 origin 4ab145f7b7e3c4e4617cbff3743fde7dff802ebd \
    && git show 4ab145f7b7e3c4e4617cbff3743fde7dff802ebd:tests/unit/test_command_show.py > /opt/golden/test_command_show.py \
    && test -s /opt/golden/test_command_show.py \
    && cd / \
    && rm -rf /tmp/golden-src

# Warm baseline: the project's own existing unit slice must already be green
# on the pristine parent tree (it is what the acceptance also asserts after
# the agent's change). This also exercises the pinned toolchain at build time
# so a broken dependency pin fails the build, not the trial.
RUN cd /app/src \
    && PYTHONPATH=src /usr/local/bin/python3 -m pytest -q \
         tests/unit/test_commands.py \
         tests/unit/metadata/test_metadata.py \
         -p no:cacheprovider

# Timestamp pyc caches embed the source file's extraction mtime, so a rebuild
# of the same Dockerfile at a different wall time produces different
# site-packages .pyc bytes and a manifest recorded from an earlier build can
# never match. Ship none of them: bytecode is derived from the pinned
# sources, so it is not part of the deliverable, and the verifier's
# usrlocal manifest "new file" check catches any .pyc an agent plants at
# trial time (PYTHONDONTWRITEBYTECODE=1 below means an honest run never
# recreates these caches either).
RUN find /usr/local/lib/python3.12/site-packages -type d -name __pycache__ -prune -exec rm -rf {} + \
    && find /usr/local/lib/python3.12/site-packages -type f -name '*.pyc' -delete

WORKDIR /app

# One CPU budget; keep any extension libs single-threaded.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONDONTWRITEBYTECODE=1

COPY files/ /app/