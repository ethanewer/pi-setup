# capstan-foresheet: Z3Prover/z3 fp.rem with subnormal divisor
# (upstream issue #10609, fix commit 384d2d881f544e0f3abfa21e0e3ebe6beb9821d7).
#
# The image clones the REAL upstream repository SHALLOW at the PARENT commit
# (d1f10234c50a49ee1cc7d08c87a680daf430017c), so the working tree ships the
# real bug: fpa2bv_converter::mk_rem() computes a wrong IEEE 754 remainder for
# fp.rem whenever the divisor is subnormal, because the dividend significand
# is widened by only max_exp_diff = 2^ebits - 3 bits while a subnormal
# divisor can lower the normalized exponent far enough that the exponent
# difference shifts the high bits of the dividend out before the remainder
# computation. For the pinned half-precision repro the solver answers `sat`
# (wrong; the operands fully determine the operation) where it must answer
# `unsat`. The project's own regression test for the bug (src/test/fpa.cpp,
# added by the fix commit) is extracted from the FIX commit at build time
# into /opt/golden; it is never part of this task tree and the fix commit is
# never reachable from /app/src.
#
# Toolchain: apt g++ (13), cmake (3.28), make on bench-base:ubuntu-24.04 -
# the same line the project's own build instructions use; apt packages are
# deliberately not version-pinned in this suite. The warm pass configures a
# Release build of both the shell target (z3 binary) and the project's unit
# test harness (test-z3) so that every later step on 1 CPU is strictly
# incremental.
#
# A build-time smoke step plants the golden regression test, rebuilds the
# harness and REQUIRES it to fail inside this image (assertion violation on
# the parent's `sat` answer), proving the image ships the bug at the pinned
# dependency versions (fail closed if it does not reproduce); the tree is
# restored byte-exact afterwards.
ARG UPSTREAM_SHA_PARENT=d1f10234c50a49ee1cc7d08c87a680daf430017c
ARG UPSTREAM_SHA_FIX=384d2d881f544e0f3abfa21e0e3ebe6beb9821d7
ARG GOLDEN_SHA=b5bed2720afa7cdbba4ad9ddc22ed68f03f84b758a1f9c9a5a8147d3530ddba9

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG GOLDEN_SHA

RUN apt-get update \
 && apt-get install -y --no-install-recommends g++ cmake make \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/
RUN chmod a+rx /app/plant_golden.sh 2>/dev/null || true \
 && chmod a+rwX /app

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
#
# The image is built as root but the trial may run as uid 1000 (user
# `ubuntu` in the base image), so the tree is made world-readable/writable
# (a+rwX) and owned by 1000:1000 right here, in the SAME RUN that creates
# it. Docker layers are copy-on-write: doing the chown/chmod in a later RUN
# would copy the whole tree (source + .git) into a new layer, storing the
# same bytes twice (measured: +40 MB of pure duplication here). Inside the
# creating layer a chown costs nothing extra.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/Z3Prover/z3.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && { chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true; }

# Extract the project's own regression test for this bug (the file the fix
# commit adds) into /opt/golden using a THROWAWAY clone that is deleted
# immediately afterwards, so upstream test bytes never land in this task
# tree and the fix commit never lands in /app/src. The file's sha256 is
# asserted so a moved commit fails closed.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/Z3Prover/z3.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:src/test/fpa.cpp > /opt/golden/fpa.cpp \
 && test "$(sha256sum /opt/golden/fpa.cpp | cut -d' ' -f1)" = "${GOLDEN_SHA}" \
 && grep -q "test_rem_subnormal_divisor" /opt/golden/fpa.cpp \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# WARM every cache the trial needs AS uid 1000 (the tree is already owned by
# 1000:1000 from the clone RUN above). The warm pass compiles the shell
# target (the z3 binary) and the project's unit test harness (test-z3) with
# the project's own cmake recipe; the trial has no network, so this layer IS
# the warm cache and the agent's rebuild is strictly incremental.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && \
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release > /tmp/warm_cfg.log 2>&1 && \
    (cmake --build build --target shell -j$(nproc) > /tmp/warm_shell.log 2>&1) && \
    (cmake --build build --target test-z3 -j$(nproc) > /tmp/warm_test.log 2>&1)'; rc=$?; \
    tail -3 /tmp/warm_cfg.log; tail -2 /tmp/warm_shell.log; tail -2 /tmp/warm_test.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    test -x /app/src/build/z3 && echo "z3 binary built" || { echo "no z3 binary"; exit 1; }; \
    test -x /app/src/build/test-z3 && echo "test-z3 harness built" || { echo "no test-z3 binary"; exit 1; }

# Smoke: prove the image ships the FAILING state. Plant the golden upstream
# regression test, rebuild the harness incrementally, and require the test to
# FAIL with an assertion violation (the parent answers `sat` to a fully
# pinned query that must be `unsat`). If the pinned dependency versions do
# not reproduce the bug, this layer fails and the image is never built.
# Restore the tree to a pristine, exactly-parent state afterwards.
RUN su -s /bin/bash ubuntu -c 'set -e; cd /app/src; \
    bash /app/plant_golden.sh; \
    cmake --build build --target test-z3 -j$(nproc) > /tmp/smoke_build.log 2>&1; \
    if ./build/test-z3 fpa > /tmp/smoke_run.log 2>&1; then \
        echo "SMOKE FAIL: golden regression test PASSED at the parent commit (bug absent)"; \
        tail -20 /tmp/smoke_run.log; exit 1; \
    fi; \
    grep -q "ASSERTION VIOLATION" /tmp/smoke_run.log || { \
        echo "SMOKE FAIL: no assertion violation in test output"; tail -20 /tmp/smoke_run.log; exit 1; }; \
    git checkout -- src/test/main.cpp src/test/CMakeLists.txt; \
    rm -f src/test/fpa.cpp; \
    test -z "$(git status --porcelain)"'
RUN echo "SMOKE OK: golden regression test fails at the parent commit inside this image"

CMD ["/bin/bash"]