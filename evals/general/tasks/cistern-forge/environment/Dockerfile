FROM bench-base:python-3.12

# ---------------------------------------------------------------------------
# cistern-forge: repair a real upstream bug in psycopg/psycopg.
#
# The checkout is pinned to the PARENT of the upstream fix: commit f9078032
# (immediately before upstream commit b9f19689 fixed issue #1327). The agent
# gets the genuine repository with the genuine bug present.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor the later
# regression-test commit (5369bbc9) is reachable from /app/src; see also the
# golden-test extraction below, which uses a throwaway clone that is deleted.
# ---------------------------------------------------------------------------
ARG UPSTREAM_SHA=f9078032c2ccd64ec351b3ab7bdeb257b2480977
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/psycopg/psycopg.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---------------------------------------------------------------------------
# Golden regression tests: the project's own tests for this bug, extracted
# from the fix branch (commit 5369bbc9, the 'main loop of each of the wait
# functions' test commit) in a throwaway clone that is deleted afterwards, so
# the fix or regression commits never land inside /app/src. The verifier
# swaps these files over the repo's copies at grading time.
# ---------------------------------------------------------------------------
ARG TEST_SHA=5369bbc9286f94cc2ed983288a607082e60f0371
RUN git clone --depth 1 --no-checkout https://github.com/psycopg/psycopg.git /tmp/psy-golden \
 && cd /tmp/psy-golden \
 && git fetch --depth 1 origin ${TEST_SHA} \
 && mkdir -p /opt/golden \
 && git show ${TEST_SHA}:tests/test_waiting.py > /opt/golden/test_waiting.py \
 && git show ${TEST_SHA}:tests/test_waiting_async.py > /opt/golden/test_waiting_async.py \
 && test -s /opt/golden/test_waiting.py \
 && test -s /opt/golden/test_waiting_async.py \
 && rm -rf /tmp/psy-golden \
 && chmod 444 /opt/golden/test_waiting.py /opt/golden/test_waiting_async.py

# ---------------------------------------------------------------------------
# Runtime and test environment, fully pinned (the trial has no network).
# libpq is required at import time (psycopg.pq loads the C library); apt is
# deliberately not version-pinned in this suite.
#
# psycopg is NOT pip-installed: PYTHONPATH points straight at the source tree
# (/app/src/psycopg is the repository subdirectory that contains the
# package), so `import psycopg` resolves to the agent's editable source from
# anywhere and edits take effect with no reinstall. (An editable pip install
# is deliberately avoided: the repo root /app/src contains a directory named
# 'psycopg' without __init__.py, which shadows the installed package and even
# defeats editable-install finders whenever the repository root is on
# sys.path -- as pytest puts it there to import the tests package.)
# typing-extensions is psycopg's only runtime dependency on Python 3.12
# (typing.LiteralString/Self exist only from 3.13); it is pinned separately.
# ---------------------------------------------------------------------------
ENV PYTHONPATH=/app/src/psycopg

RUN apt-get update && apt-get install -y --no-install-recommends libpq5 \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir typing-extensions==4.16.0 pytest==9.1.1

# ---------------------------------------------------------------------------
# Site-free source-integrity check dependency: the verifier re-runs the two-
# phase repro under `python3 -S` so that no site-packages injection
# (sitecustomize.py / .pth files) can satisfy it -- the fix must live in the
# /app/src source itself. With -S the python site machinery (and therefore
# typing-extensions, psycopg's only 3.12 runtime dep) is off sys.path, so a
# pinned copy of the module is staged here. provenance_check.py verifies its
# SHA-256 so tampering with the check dependency cannot silence the gate.
# ---------------------------------------------------------------------------
RUN mkdir -p /opt/checkdeps \
 && cp "$(python3 -c 'import typing_extensions; print(typing_extensions.__file__)')" /opt/checkdeps/typing_extensions.py \
 && python3 -c "import hashlib; d=open('/opt/checkdeps/typing_extensions.py','rb').read(); assert hashlib.sha256(d).hexdigest()=='4040ca1a1ecbee00d1385c12a93084d1c5bd46f0b774f07e5ae7e91c4f55e696', 'checkdeps copy, not the pinned typing_extensions'" \
 && chmod 444 /opt/checkdeps/typing_extensions.py

WORKDIR /app

COPY files/ /app/