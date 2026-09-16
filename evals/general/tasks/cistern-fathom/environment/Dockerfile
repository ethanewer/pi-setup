FROM bench-base:python-3.12

# ---------------------------------------------------------------------------
# cistern-fathom: repair a real upstream bug in pallets/werkzeug.
#
# The checkout is pinned to the PARENT of the upstream fix: commit 4c09d1b3
# (werkzeug 3.0.1-era main, immediately before upstream commit f516c400 fixed
# issue #2842). The agent gets the genuine repository with the genuine bug
# present. The fix commit objects are deliberately never fetched into this
# clone: we shallow-clone the 3.0.1 tag, fetch exactly the parent SHA over a
# --depth 1 boundary, and detach there. The only remaining ref is the 3.0.1
# tag (an ancestor of the parent), so the fix is not reachable from /app/src.
# ---------------------------------------------------------------------------
ARG UPSTREAM_SHA=4c09d1b3b08deb939803a4beb53483cbc54dfb8d
ARG UPSTREAM_TAG=3.0.1
RUN git clone --depth 1 --branch ${UPSTREAM_TAG} https://github.com/pallets/werkzeug.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q --detach ${UPSTREAM_SHA} \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---------------------------------------------------------------------------
# Golden regression test: the project's own test for this bug, extracted from
# the FIX commit in a throwaway clone that is deleted afterwards, so the fix
# commit object never lands inside /app/src. The verifier swaps this file over
# the repo's copy of tests/test_datastructures.py at grading time.
# ---------------------------------------------------------------------------
ARG FIX_SHA=f516c4005c7c4510b61ae07969450771b929809d
RUN git clone --depth 1 --no-checkout https://github.com/pallets/werkzeug.git /tmp/wz-golden \
 && cd /tmp/wz-golden \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:tests/test_datastructures.py > /opt/golden/test_datastructures.py \
 && test -s /opt/golden/test_datastructures.py \
 && rm -rf /tmp/wz-golden \
 && chmod 444 /opt/golden/test_datastructures.py

# ---------------------------------------------------------------------------
# Python environment, fully pinned (the trial has no network). The project's
# own dev pins from requirements/tests.txt (pytest, pytest-xprocess,
# ephemeral-port-reserve) plus its one runtime dependency MarkupSafe. Werkzeug
# is installed editable so `import werkzeug` resolves straight into
# /app/src/src/werkzeug and the agent's edits take effect with no reinstall.
# ---------------------------------------------------------------------------
RUN pip install --no-cache-dir MarkupSafe==3.0.2 flit_core==3.12.0 \
 && pip install --no-cache-dir --no-build-isolation --no-deps -e /app/src \
 && pip install --no-cache-dir pytest==7.4.0 pytest-xprocess==0.22.2 ephemeral-port-reserve==1.1.4

WORKDIR /app

COPY files/ /app/