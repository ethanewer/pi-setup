# garboard-yard: psutil process_iter() silently omits zombie processes.
#
# The image clones giampaolo/psutil SHALLOW at the PARENT commit (real upstream
# issue #2793 present in the working tree) and installs it EDITABLE
# (`pip install -e .`), so the agent's edits to the sources in /app/src take
# effect on the next `import psutil` without any rebuild; the C extensions are
# compiled once at build time. The FIX commit (73a2bfb9...) is fetched only
# into a throwaway bare clone under /tmp that is deleted afterwards, so the
# fix is never reachable from /app/src/.git and the agent cannot read the
# answer with `git log --all` (the clone has no other refs anyway: depth 1 at
# the parent plus the default-branch tip removed by the detached checkout).
#
# The golden test (TestProcessIter::test_zombie_process_is_not_skipped) is
# extracted from the FIX commit at build time into /opt/golden (sha-asserted
# so the build fails closed if upstream moves) and also overlaid onto the
# pristine pre-fix snapshot /opt/psutil-prefix/tests/, so the verifier can run
# the project's own regression test against both the pre-fix tree concept
# (an isolated venv at /opt/prefix-venv that cannot see the editable install)
# and the agent's repaired tree. A build-time smoke step re-confirms the mined
# failure state inside this image: the golden test and the direct
# reproduction must FAIL against the pre-fix tree, or the build stops.
#
# psutil is not a Terminal-Bench 2.1 source repository (checked against
# specs/tb21_source_repositories.json).
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

ARG UPSTREAM_SHA=1ae01d1210f73b411d38c0b7dc365727ae07608d
ARG FIX_SHA=73a2bfb9152b20a85b4ea51d71b5d139c174aa02
# sha256 of tests/test_system.py AT THE FIX COMMIT (contains the golden test)
ARG GOLDEN_SHA=92e9474a913fc0077e7faa477bec7222df95818eb06660737ccf006b82af86b4

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- build toolchain ---------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev linux-libc-dev \
 && rm -rf /var/lib/apt/lists/*

# ---- working clone: buggy parent commit, fix commit unreachable --------------
RUN git clone --depth 1 https://github.com/giampaolo/psutil.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 1ae01d1210f73b411d38c0b7dc365727ae07608d \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- editable install: compiles the C extensions in-tree ----------------------
RUN python3 -m pip install --no-cache-dir setuptools==75.3.2 \
 && cd /app/src \
 && python3 -m pip install --no-cache-dir --no-build-isolation --no-deps -e .

# ---- test tooling (pinned to versions resolved on this base) ------------------
RUN python3 -m pip install --no-cache-dir \
      pytest==8.3.4 pytest-instafail==0.5.0 pytest-xdist==3.6.1

# ---- pristine pre-fix snapshot of the tree (no git history) -------------------
# The C extensions from the editable build live in-tree, so the snapshot is a
# complete runnable pre-fix psutil on its own.
RUN cp -a /app/src /opt/psutil-prefix \
 && rm -rf /opt/psutil-prefix/.git \
           /opt/psutil-prefix/build \
           /opt/psutil-prefix/*.egg-info \
 && find /opt/psutil-prefix -name __pycache__ -type d -prune -exec rm -rf {} \;

# ---- extract the upstream regression test from the FIX commit -----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/giampaolo/psutil.git \
 && git fetch --depth 1 origin 73a2bfb9152b20a85b4ea51d71b5d139c174aa02 \
 && mkdir -p /opt/golden \
 && git show 73a2bfb9152b20a85b4ea51d71b5d139c174aa02:tests/test_system.py \
      > /opt/golden/test_system.py \
 && test "$(sha256sum /opt/golden/test_system.py | cut -d' ' -f1)" = "$GOLDEN_SHA" \
 && grep -q "test_zombie_process_is_not_skipped" /opt/golden/test_system.py \
 && cp /opt/golden/test_system.py /opt/psutil-prefix/tests/test_system.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- pre-fix python environment, isolated from the editable install -----------
# pip>=21 editable installs hook sys.meta_path, which shadows any PYTHONPATH,
# so the pre-fix tree concept runs under its own venv that has the pre-fix
# psutil installed non-editable.
RUN python3 -m venv /opt/prefix-venv \
 && /opt/prefix-venv/bin/pip install --no-cache-dir \
      setuptools==75.3.2 wheel==0.45.1 pytest==8.3.4 \
      pytest-instafail==0.5.0 pytest-xdist==3.6.1 \
 && /opt/prefix-venv/bin/pip install --no-cache-dir \
      --no-build-isolation --no-deps /opt/psutil-prefix

# ---- build-time smoke: the mined failing state must reproduce -----------------
# The golden test and the direct reproduction must FAIL against the pristine
# pre-fix tree/installation exactly as the mining run observed. If our
# dependency pins changed the behaviour, the image build fails closed.
RUN cd /opt/psutil-prefix && python3 -m pytest \
      tests/test_system.py -k test_zombie_process_is_not_skipped \
      -q -p no:cacheprovider > /tmp/smoke-golden.log 2>&1; \
    rc=$?; \
    if [ "$rc" -eq 0 ]; then \
      echo "golden test PASSED against the pre-fix tree (build fails closed)" >&2; \
      cat /tmp/smoke-golden.log >&2; exit 1; \
    fi
RUN python3 - <<'PY'
import os
import unittest.mock as mock
import psutil

list(psutil.process_iter())
p = psutil._pmap[os.getpid()]
with mock.patch.object(p, "as_dict", side_effect=psutil.ZombieProcess(p.pid)):
    pids = [x.pid for x in psutil.process_iter(attrs=["name"])]
assert os.getpid() not in pids, "mined failure state did not reproduce"
print("smoke: pre-fix tree omits the zombie-condition process, as mined")
PY

# ---- permissions ---------------------------------------------------------------
# The trial runs as uid 1000 and must edit the working tree; the ground truth
# (pre-fix snapshot, golden test, prefix venv) is read-only to it.
RUN chmod -R a+rwX /app/src \
 && chmod -R a+rX /opt/psutil-prefix /opt/golden /opt/prefix-venv \
 && chmod -R o-w /opt

WORKDIR /app

CMD ["/bin/bash"]