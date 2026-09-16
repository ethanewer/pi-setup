# ---------------------------------------------------------------------------
# ballast-roadstead: `poetry debug resolve` crashes with IndexError when a
# resolved package carries an environment marker (upstream issue #10807).
#
# The image clones python-poetry/poetry into /app/src and checks out the
# upstream PARENT commit b760721672011534ca3607d17e3bf61a4dc6ed90 (immediately
# before fix commit 89aaee9d60cae20775d3c40e4f243f9945f718e1), so the agent
# gets the real repository with the real bug still in it. The clone is created
# with `git init` + a single `git fetch --depth 1 origin <parent-sha>` and
# detached there, so the ONLY commit object in the /app/src object store is
# the parent itself: neither the fix commit nor any later history is reachable
# from /app/src, and `git rev-list --all --count` is exactly 1.
#
# The project's own regression test for the bug is extracted from the FIX
# commit at image build time into /opt/golden/ (upstream bytes never enter
# this repository), using a throwaway clone that is deleted afterwards.
#
# The project venv (/opt/poetry-venv) is pre-built with poetry-core pinned to
# the exact lock ref the mining container used (b9663e42...) so `pip install
# -e .` cannot drift to poetry-core main, plus every runtime/test dependency.
# A build-time smoke run proves the shipped state is the mined failing state:
# the golden regression test fails with
# `IndexError: list assignment index out of range` before the tree is
# restored to the pristine parent checkout.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=b760721672011534ca3607d17e3bf61a4dc6ed90
ARG FIX_SHA=89aaee9d60cae20775d3c40e4f243f9945f718e1

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/python-poetry/poetry.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes also never enter this repository; the golden
# file lives only in the image at /opt/golden/.
RUN git clone --depth 1 --no-checkout https://github.com/python-poetry/poetry.git /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:tests/console/commands/debug/test_resolve.py \
      > /opt/golden/test_resolve.py \
 && test -s /opt/golden/test_resolve.py \
 && grep -q "def test_debug_resolve_shows_marker_when_present" /opt/golden/test_resolve.py \
 && cd / && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_resolve.py

# ---- environment: the project venv, fully installed and pinned --------------
# The trial has no network: everything the agent or the tests import must
# already be in the image. The recipe below mirrors the environment in which
# the reproduction was verified upstream.
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN python3 -m venv /opt/poetry-venv \
 && /opt/poetry-venv/bin/pip install \
      "poetry-core @ git+https://github.com/python-poetry/poetry-core.git@b9663e42c808543377ae523611c4cfad68016f30" \
 && cd /app/src \
 && /opt/poetry-venv/bin/pip install -e . --no-deps \
 && /opt/poetry-venv/bin/pip install build==1.6.1 \
      "cachecontrol[filecache]==0.14.4" cleo==2.1.0 dulwich==1.2.14 \
      fastjsonschema==2.22.2 installer==1.0.1 keyring==25.7.0 \
      packaging==26.3 pkginfo==1.13 platformdirs==4.11.8 \
      pyproject-hooks==1.2.0 requests==2.34.2 requests-toolbelt==1.0.0 \
      shellingham==1.5.4 tomlkit==0.15.1 trove-classifiers==2026.6.1.19 \
      virtualenv==21.7.9 findpython==0.8.0 \
      "pbs-installer[download,install]==2026.9.1" deepdiff==9.1.0 \
      pytest==9.1.1 pytest-mock==3.15.1 \
      "pytest-xdist[psutil]==3.8.0" responses==0.26.3

# ---- smoke: the shipped state must be the mined failing state ---------------
# The golden regression test against the buggy tree fails with the mined
# IndexError; the tree is then restored to the pristine parent checkout.
RUN cp /opt/golden/test_resolve.py /app/src/tests/console/commands/debug/test_resolve.py \
 && cd /app/src \
 && /opt/poetry-venv/bin/pytest tests/console/commands/debug/test_resolve.py \
      -k test_debug_resolve_shows_marker_when_present --no-header \
      -p no:randomly -o addopts="" > /tmp/smoke.log 2>&1 || true \
 && grep -qF "IndexError: list assignment index out of range" /tmp/smoke.log \
 && git -C /app/src checkout -- tests/console/commands/debug/test_resolve.py \
 && test -z "$(git -C /app/src status --porcelain)" \
 && tail -6 /tmp/smoke.log

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]