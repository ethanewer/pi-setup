# chainplate-caboose: pypa/setuptools archive extraction lets backslash,
# drive-letter and UNC archive member names escape the extraction directory
# (security advisory GHSA-grgh-hr87-3jpw upstream).
#
# The image clones pypa/setuptools SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree), extracts the project's own
# regression tests for the bug from the FIX commit at build time into
# /opt/golden/, and overlays them over the tree's own test module, so
# `python3 -m pytest -q setuptools/tests/test_archive_util.py` fails inside
# the image with the mined symptom ('7 failed, 7 passed, 1 xpassed'). The
# fix commit is fetched only into a throwaway bare clone that is deleted, so
# it is never reachable from /app/src.
#
# The base image's Python lacks the stdlib `test` package, which the
# project's test collection needs through setuptools/tests/compat/py39.py
# (`from test.support import os_helper` via jaraco.test); the remedy is to
# copy CPython 3.12.13's Lib/test into the interpreter's stdlib directory.
#
# Neither pypa/setuptools nor python/cpython is a Terminal-Bench 2.1 source
# repository (checked against specs/tb21_source_repositories.json, which
# lists neither).
#
# A smoke RUN at the end fails the build unless the mined buggy state is
# present, so a rebuild that drifts (different parent, moved golden file,
# changed base) cannot silently ship a task whose bug no longer reproduces.
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1

ARG PARENT_SHA=bb1b38189eed960bdb4f4789926472d05e43d335
ARG FIX_SHA=72974110e29d53080dcf23cfa52d9c17299dbae4
ARG CPYTHON_TAG=v3.12.13
ARG CPYTHON_SHA=3bb231a6a5dc02b95658877318bf61501a7209e9

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable -------------
RUN git clone --depth 1 https://github.com/pypa/setuptools.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin ${PARENT_SHA} \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${PARENT_SHA}" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- stdlib `test` package required by the project's own test collection ----
RUN git clone --depth 1 --branch ${CPYTHON_TAG} \
        https://github.com/python/cpython.git /tmp/cpython \
 && test "$(git -C /tmp/cpython rev-parse HEAD)" = "${CPYTHON_SHA}" \
 && cp -r /tmp/cpython/Lib/test /usr/local/lib/python3.12/test \
 && rm -rf /tmp/cpython \
 && python3 -c "from test.support import os_helper; assert os_helper.can_symlink(), 'no symlink support'"

# ---- extract the upstream regression tests from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/pypa/setuptools.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:setuptools/tests/test_archive_util.py \
      > /opt/golden/test_archive_util.py \
 && test "$(sha256sum < /opt/golden/test_archive_util.py | cut -d' ' -f1)" \
      = "0bf96f6d993cb9dfca413b2078890fbe9e9d6dcb4e23ea5d4a25202c49d39970" \
 && cd / \
 && rm -rf /tmp/fixsrc

# ---- overlay the upstream regression tests over the tree's own test module ---
RUN cp /opt/golden/test_archive_util.py /app/src/setuptools/tests/test_archive_util.py

# ---- dependencies (pytest pinned per slot; editable install of the project) --
# The repo's pytest.ini references warnings from module coverage.exceptions, so
# coverage must be importable for pytest to start at all.
RUN pip install --no-cache-dir 'pytest==8.4.2' 'coverage==7.16.0' \
 && cd /app/src \
 && pip install --no-cache-dir -e '.[test]' \
 && python3 -c "import pytest; assert pytest.__version__ == '8.4.2'" \
 && python3 -c "import setuptools; import os; assert os.path.dirname(setuptools.__file__) == '/app/src/setuptools', setuptools.__file__"

# ---- snapshot the interpreter's import hooks -------------------------------
# The trial runs as root in a container shared with the verifier, so a wrapper
# smuggled into site-packages (sitecustomize.py / usercustomize.py / a stray
# .pth) would let an agent "fix" the bug outside the deliverable tree. The
# verifier recomputes this inventory and fails the run on any drift.
RUN find /usr/local/lib/python3.12/site-packages /root/.local/lib/python3.12/site-packages \
        -maxdepth 1 \( -name 'sitecustomize.py' -o -name 'usercustomize.py' -o -name '*.pth' \) \
        -printf '%f|%s|%T@\n' 2>/dev/null | sort > /opt/site-hooks-inventory.txt \
 && wc -l /opt/site-hooks-inventory.txt

# ---- build-time smoke: the image must ship the mined buggy state ------------
COPY files/ /app/
RUN python3 /app/smoke_parent.py \
 && rm -f /app/smoke_parent.py \
 && rm -rf /app/src/.pytest_cache

# The trial may run as an unprivileged user: open the tree for edits.
RUN chmod -R a+rwX /app/src

WORKDIR /app
CMD ["/bin/bash"]