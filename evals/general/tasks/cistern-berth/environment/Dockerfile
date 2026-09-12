# cistern-berth: fix a real infinite-loop bug in aiohttp's Forwarded-header
# parsing inside a SHA-pinned upstream clone.
#
# Bakes in a shallow, SHA-pinned clone of aio-libs/aiohttp at the BUGGY
# parent revision (956f140, the commit immediately before aiohttp's fix
# b2b2bce for upstream issue #13229) with a pure-Python editable install, so
# the agent gets the real repository with the real bug still present:
# reading request.forwarded spins forever when the Forwarded header ends
# with an empty or malformed element ("Forwarded: ; a" or "Forwarded: a").
#
# The upstream regression test added by the fix commit
# (test_single_forwarded_header_trailing_bad_value) is extracted to
# /opt/golden/test_web_request.py at build time. Extraction happens in a
# throwaway clone that is deleted before the trial, so the fix commit is
# NEVER reachable from /app/src/.git (the verifier asserts this).
#
# Both directions are re-confirmed inside this image at build time:
#   parent: the contract probe hangs -> `timeout 15` kills it (exit 124),
#           and the golden regression test times out (fails) on the buggy
#           tree;
#   fix:    the contract probe terminates and prints CONTRACT OK, the
#           golden regression test passes (5 passed) -- this check runs in
#           the throwaway clone; /app/src ships the bug.

FROM bench-base:python-3.12

# Buggy revision and its upstream fix, both from https://github.com/aio-libs/aiohttp
ARG UPSTREAM_SHA=956f140095b21a88e11def934d42de85cc0b2b6b
ARG FIX_SHA=b2b2bce03c17521dc454cdd4a6e19ab0a08bce6b

# git-uid-1000 safety and a build identity (agents may run git commands).
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "build"

# Thread-pool pins (cpus = 1) and no bytecode writes so `git status` stays clean.
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 PYTHONDONTWRITEBYTECODE=1

# Pinned test toolchain; these exact versions are what aiohttp's own
# requirements/test-common-base.txt pins for its CI.
RUN pip install --no-cache-dir \
        pytest==9.1.1 pytest-asyncio==1.4.0 pytest-aiohttp==1.1.1 \
        pytest-timeout==2.4.0 freezegun==1.5.5 coverage==7.15.4

# Build-time contract probe (also lands in /app via the final COPY; harmless).
COPY files/probes/ /probes/

# --- Extract the golden regression test from the FIX commit (throwaway) ----
# The fix commit enters a disposable clone that is removed immediately; it
# never lands inside /app/src/.git.
RUN git init /tmp/golden-src \
    && cd /tmp/golden-src \
    && git remote add origin https://github.com/aio-libs/aiohttp.git \
    && git fetch --depth 1 origin "$FIX_SHA" \
    && mkdir -p /opt/golden \
    && git show "$FIX_SHA:tests/test_web_request.py" > /opt/golden/test_web_request.py \
    && cd / \
    && rm -rf /tmp/golden-src \
    && test -s /opt/golden/test_web_request.py \
    && grep -q "test_single_forwarded_header_trailing_bad_value" /opt/golden/test_web_request.py \
    && echo "golden test file extracted"

# --- Fix-direction self check (throwaway clone: parent + upstream fix) -----
# Proves the reproduction and the whole observable contract (contract probe
# prints CONTRACT OK, golden regression test passes) once the fixed
# web_request.py is applied on top of the pinned parent revision. Runs in
# /tmp/fixchk with an editable install; the clone and its install are
# removed afterwards.
RUN git init /tmp/fixchk \
    && cd /tmp/fixchk \
    && git remote add origin https://github.com/aio-libs/aiohttp.git \
    && git fetch --depth 1 origin "$UPSTREAM_SHA" \
    && git checkout --detach FETCH_HEAD >/dev/null 2>&1 \
    && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
    && git submodule update --init \
    && AIOHTTP_NO_EXTENSIONS=1 python3 -m pip install --no-cache-dir -e . -q \
    && git fetch --depth 1 origin "$FIX_SHA" \
    && git checkout "$FIX_SHA" -- aiohttp/web_request.py \
    && timeout 30 python3 /probes/forwarded_probe.py \
    && python3 -m pytest -q -p no:cacheprovider --rootdir=/tmp/fixchk \
        "/opt/golden/test_web_request.py::test_single_forwarded_header_trailing_bad_value" \
    && cd / \
    && rm -rf /tmp/fixchk \
    && python3 -m pip uninstall -y aiohttp >/dev/null \
    && echo "fix-direction: contract probe OK and golden regression test passed"

# --- The agent's clone: the buggy parent revision, shallow and pinned -------
RUN git init /app/src \
    && cd /app/src \
    && git remote add origin https://github.com/aio-libs/aiohttp.git \
    && git fetch --depth 1 origin "$UPSTREAM_SHA" \
    && git checkout --detach FETCH_HEAD >/dev/null 2>&1 \
    && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
    && ! git cat-file -e "$FIX_SHA^{commit}" \
    && git submodule update --init \
    && AIOHTTP_NO_EXTENSIONS=1 python3 -m pip install --no-cache-dir -e . -q \
    && ! git status --porcelain --untracked-files=all | grep -q . \
    && echo "/app/src built: HEAD pinned, fix commit absent, tree pristine"

# --- Parent-direction self check on the pristine buggy tree ----------------
# This must FAIL (the contract probe hangs -> timeout kills it, exit 124):
# it proves the bug and the environment trap are both live in the exact
# image the agent will work in.
RUN cd /app/src && timeout 15 python3 /probes/forwarded_probe.py \
    ; rc=$?; test "$rc" -eq 124 \
    && echo "parent-direction: contract probe hangs at parent (timeout 15 -> exit 124) as expected"

# The golden regression test must NOT pass on the buggy tree (it hangs).
# Each of the 5 parameters runs under pytest-timeout's --timeout=10 so the
# check stays bounded; 1 of the 5 completes, the other 4 time out.
RUN cd /app/src && timeout 240 python3 -m pytest -q -p no:cacheprovider --rootdir=/app/src \
        -p timeout --timeout=10 \
        "/opt/golden/test_web_request.py::test_single_forwarded_header_trailing_bad_value" \
        > /tmp/golden_parent.log 2>&1 \
    ; rc=$?; test "$rc" -ne 0 && grep -q "Timeout" /tmp/golden_parent.log \
    && echo "parent-direction: golden regression test times out on the buggy tree as expected" \
    || { echo "UNEXPECTED golden result on buggy tree (rc=$rc)"; cat /tmp/golden_parent.log; exit 1; }

# --- Baseline: the project's own forwarded suite is green on the pristine ---
# tree (the fix must not change what already worked).
RUN cd /app/src && python3 -m pytest -q -p no:cacheprovider --rootdir=/app/src \
        -p timeout --timeout=120 tests/test_web_request.py -k forwarded

WORKDIR /app
COPY files/ /app/

# The trial may run as uid 1000; the agent must be able to edit /app/src.
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]