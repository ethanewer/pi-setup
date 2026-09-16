ARG PARENT_SHA=4e349a7c0ba553f7b1ba281d35956f4267208f02
ARG FIX_SHA=d0b3fb3c89851f10edce10bb425676f400898e00

FROM bench-base:python-3.12

ARG PARENT_SHA
ARG FIX_SHA

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPYCACHEPREFIX=/tmp/pycache

# mypy's own runtime + test dependencies, pinned exactly to the versions the
# project's test-requirements.txt at the pinned parent commit specifies
# (resolved against this base image's interpreter). Everything mypy needs at
# trial time is baked into the image; the trial has no network.
RUN pip install --no-cache-dir \
      typing_extensions==4.15.0 \
      mypy_extensions==1.1.0 \
      pathspec==1.0.0 \
      librt==0.10.0 \
      ast-serialize==0.3.0 \
      pytest==8.4.2 \
      pytest-xdist==3.8.0 \
      lxml==6.0.2 \
      attrs==25.4.0 \
 && python3 -c "import mypy_extensions, typing_extensions, librt, ast_serialize, lxml, pytest" \
 && echo "pinned deps installed ok"

# The container may run the trial as root or as uid 1000; git must accept the
# root-owned clone either way, and build-time commits need an identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && useradd -m -u 1000 -s /bin/bash ubuntu 2>/dev/null || true

# ---------------------------------------------------------------------------
# 1. The REAL upstream repository (python/mypy) at exactly the parent commit,
#    as a single depth-1 fetch: the object store holds exactly one commit, so
#    the fix commit (which the agent must not be able to look up or fetch) is
#    provably absent. Fails closed if the pin moves.
# ---------------------------------------------------------------------------
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/python/mypy.git \
 && git fetch --depth 1 origin ${PARENT_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${PARENT_SHA}" \
 && test -z "$(git status --porcelain)" \
 && echo "parent pin ok, tree clean: $(git rev-parse HEAD)"

# ---------------------------------------------------------------------------
# 2. A pristine PRE-FIX copy of the tree at /opt/mypy-parent (no .git, no test
#    additions), which the verifier uses to prove the agent's reproduction
#    genuinely fails on the un-repaired code. Recorded sha256 anchors for the
#    integrity check.
# ---------------------------------------------------------------------------
RUN cd /app/src \
 && mkdir -p /opt/mypy-parent /opt/pins \
 && git archive HEAD | tar -x -C /opt/mypy-parent \
 && test -f /opt/mypy-parent/mypy/subtypes.py \
 && test -f /opt/mypy-parent/pyproject.toml \
 && echo "parent tree archived"

# ---------------------------------------------------------------------------
# 3. Extract the project's own regression test for this bug from the FIX
#    commit through a THROWAWAY clone that is deleted immediately afterwards,
#    so the fix commit never enters /app/src and no fix bytes enter the task
#    tree. The golden case is the [case testTypeVarValuesSubtypeOfAll] block
#    that upstream appended to test-data/unit/check-typevar-values.test.
# ---------------------------------------------------------------------------
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/python/mypy.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${FIX_SHA}" \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:test-data/unit/check-typevar-values.test \
      | sed -n '/^\[case testTypeVarValuesSubtypeOfAll\]/,$p' \
      > /opt/golden/golden-case.test \
 && test -s /opt/golden/golden-case.test \
 && grep -q '^\[case testTypeVarValuesSubtypeOfAll\]$' /opt/golden/golden-case.test \
 && grep -q 'Incompatible default for parameter' /opt/golden/golden-case.test \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && echo "golden regression test extracted, fix clone destroyed"

# ---------------------------------------------------------------------------
# 4. Parent-direction confirmation INSIDE this image, on the exact pinned
#    deps the trial will use: the bug must reproduce here. The direct CLI
#    reproduction reports TWO 'Incompatible default for parameter' errors,
#    including the false positive on the legal default (line 7); the check
#    fails closed if anything is off. Also confirmed as uid 1000.
# ---------------------------------------------------------------------------
RUN cat > /tmp/reprocheck.py <<'PY'
from typing import TypeVar
class B: ...
class C(B): ...
S = TypeVar("S", B, C)
b = B()
c = C()
def g(x: S = c):  # valid: c: C is one of S's value types
    pass
def h(x: S = b):  # invalid: b: B is not a subtype of C
    pass
PY
RUN cd /app/src \
 && python3 -m mypy --no-incremental --cache-dir=/tmp/mycache /tmp/reprocheck.py > /tmp/parent-repro.out 2>&1; rc=$?; \
    echo "parent repro rc=$rc" | tee -a /tmp/parent-repro.out; \
    cat /tmp/parent-repro.out; \
    if [ "$rc" -eq 0 ]; then echo "parent repro did NOT fail - bug missing"; exit 1; fi; \
    if [ "$(grep -c 'Incompatible default for parameter' /tmp/parent-repro.out)" -ne 2 ]; then \
      echo "expected exactly 2 'Incompatible default' errors"; exit 1; fi; \
    grep -q 'default has type "C", parameter has type "S"' /tmp/parent-repro.out || { echo "false positive on the legal default not seen"; exit 1; }
RUN su -s /bin/bash ubuntu -c 'cd /app/src && python3 -m mypy --no-incremental --cache-dir=/tmp/mycache-u /tmp/reprocheck.py > /tmp/parent-repro-u.out 2>&1'; rc=$?; \
    echo "uid1000 repro rc=$rc"; \
    if [ "$rc" -eq 0 ]; then echo "uid1000: bug did not reproduce"; exit 1; fi; \
    grep -q 'Incompatible default for parameter' /tmp/parent-repro-u.out || { echo "uid1000: false positive not seen"; exit 1; }

# ---------------------------------------------------------------------------
# 5. Golden-direction confirmation inside this image (parent COPY): with the
#    upstream regression case planted, the data test must FAIL at the parent
#    commit and every pre-existing type-variable test must still PASS.
# ---------------------------------------------------------------------------
RUN git clone --depth 1 -q /app/src /tmp/parentcheck \
 && cat /opt/golden/golden-case.test >> /tmp/parentcheck/test-data/unit/check-typevar-values.test \
 && cd /tmp/parentcheck \
 && python3 -m pytest mypy/test/testcheck.py -k testTypeVarValuesSubtypeOfAll -n 1 -q > /tmp/golden-parent.out 2>&1; rc=$?; \
    tail -4 /tmp/golden-parent.out; \
    if [ "$rc" -eq 0 ]; then echo "golden case PASSED at parent - test does not cover the bug"; exit 1; fi; \
    cd /tmp/parentcheck \
 && python3 -m pytest mypy/test/testcheck.py -k "check-typevar" -n 1 -q > /tmp/sweep-parent.out 2>&1; rc=$?; \
    tail -2 /tmp/sweep-parent.out; \
    grep -q '1 failed, 219 passed' /tmp/sweep-parent.out || { echo "expected exactly 1 failed (golden) + 219 passed at parent"; exit 1; } \
 && rm -rf /tmp/parentcheck \
 && echo "parent direction confirmed: golden FAILS, 219 existing cases PASS"

# ---------------------------------------------------------------------------
# 6. Fix-direction confirmation inside this image (throwaway FIX clone,
#    deleted afterwards): the direct reproduction must be reduced to the one
#    genuinely invalid error, and the golden regression test must PASS.
# ---------------------------------------------------------------------------
RUN git init -q /tmp/fixcheck \
 && cd /tmp/fixcheck \
 && git remote add origin https://github.com/python/mypy.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${FIX_SHA}" \
 && cd /tmp/fixcheck \
 && python3 -m mypy --no-incremental --cache-dir=/tmp/mycache-f /tmp/reprocheck.py > /tmp/fix-repro.out 2>&1; rc=$?; \
    cat /tmp/fix-repro.out; \
    if [ "$rc" -eq 0 ]; then echo "fix tree accepted a genuinely invalid default"; exit 1; fi; \
    if [ "$(grep -c 'Incompatible default for parameter' /tmp/fix-repro.out)" -ne 1 ]; then \
      echo "expected exactly 1 'Incompatible default' error at fix"; exit 1; fi; \
    grep -q 'default has type "B", parameter has type "S"' /tmp/fix-repro.out || { echo "the invalid default error not seen at fix"; exit 1; } \
 && cd /tmp/fixcheck \
 && python3 -m pytest mypy/test/testcheck.py -k testTypeVarValuesSubtypeOfAll -n 1 -q > /tmp/golden-fix.out 2>&1; rc=$?; \
    tail -2 /tmp/golden-fix.out; \
    if [ "$rc" -ne 0 ]; then echo "golden case FAILED at fix commit"; exit 1; fi; \
    grep -q '1 passed' /tmp/golden-fix.out || { echo "golden did not report 1 passed"; exit 1; } \
 && cd /tmp/fixcheck \
 && python3 -m pytest mypy/test/testcheck.py -k "check-typevar" -n 1 -q > /tmp/sweep-fix.out 2>&1; rc=$?; \
    tail -2 /tmp/sweep-fix.out; \
    if [ "$rc" -ne 0 ]; then echo "typevar sweep failed at fix commit"; exit 1; fi; \
    grep -q '220 passed' /tmp/sweep-fix.out || { echo "expected 220 passed at fix (219 + golden)"; exit 1; } \
 && cd / \
 && rm -rf /tmp/fixcheck \
 && echo "fix direction confirmed: golden PASSES + sweep green in this image"

# ---------------------------------------------------------------------------
# 7. Belt: prove the fix commit is not reachable from the trial clone (only
#    the parent commit was ever fetched into it), and record the integrity
#    anchors the verifier will check.
# ---------------------------------------------------------------------------
RUN cd /app/src \
 && if git cat-file -e ${FIX_SHA}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; fi \
 && test "$(git rev-parse HEAD)" = "${PARENT_SHA}" \
 && test "$(git rev-parse --verify HEAD)" = "${PARENT_SHA}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)" \
 && cd /app/src \
 && sha256sum mypy/subtypes.py mypy/checker.py mypy/main.py mypy/__main__.py \
        test-data/unit/check-typevar-values.test pyproject.toml \
      > /opt/pins/parent-tree.sha256 \
 && sha256sum /opt/golden/golden-case.test > /opt/pins/golden.sha256 \
 && sha256sum /opt/mypy-parent/mypy/subtypes.py > /opt/pins/prefix-subtypes.sha256 \
 && sha256sum /usr/local/bin/python3 "$(python3 -c 'import typing_extensions; print(typing_extensions.__file__)')" /usr/local/bin/pip3 \
      > /opt/pins/toolchain.sha256 \
 && test "$(wc -l < /opt/pins/parent-tree.sha256)" -eq 6 \
 && test "$(wc -l < /opt/pins/toolchain.sha256)" -eq 3 \
 && sha256sum -c /opt/pins/parent-tree.sha256 >/dev/null \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-subtypes.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "integrity anchors recorded"

# ---------------------------------------------------------------------------
# 7.5 Wipe every build-time scratch file under /tmp. The mypy cache DBS carry
#     the git-revision stamp of the tree that populated them, including the
#     FIX commit SHA written by the fix-direction confirmations above; pytest
#     and mypy logs from those runs also linger here. Nothing under /tmp from
#     the build is needed at trial time, so none of it may ship.
# ---------------------------------------------------------------------------
RUN rm -rf /tmp/mycache /tmp/mycache-f /tmp/mycache-u /tmp/pycache /tmp/pytest-of-root \
           /tmp/reprocheck.py /tmp/parent-repro.out /tmp/parent-repro-u.out \
           /tmp/fix-repro.out /tmp/golden-fix.out /tmp/golden-parent.out \
           /tmp/sweep-fix.out /tmp/sweep-parent.out \
 && rm -f /tmp/pathset.diff \
 && test -z "$(ls -A /tmp 2>/dev/null | grep -v node-compile-cache)" \
 && echo "build scratch under /tmp wiped"

# Make the pristine pre-fix tree and the anchors read-only for uid 1000
# (root can always rewrite anything; uid 1000 cannot tamper here).
RUN chown -R root:root /opt \
 && find /opt/mypy-parent /opt/golden -type f -exec chmod 444 {} + \
 && find /opt/mypy-parent -type d -exec chmod 555 {} + \
 && chmod 555 /opt/golden /opt/pins \
 && chmod 444 /opt/pins/*.sha256

# Hand the working tree to the trial user: all writable regardless of uid,
# but ownership is uid 1000 so build-time artifacts are usable by either.
RUN chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src

COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/README-BUILD.md

WORKDIR /app

CMD ["/bin/bash"]