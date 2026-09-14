# corvette-towpath: Z3Prover/z3 binary16 fp.fma one-ulp mis-rounding
# (upstream issue #10608; fix commit 8d32b2b02ab31c5cd293362866fa32f6eab75e09,
# parent e950cd371c3ca16823079feded145bc6ce3feb95).
#
# The image clones the REAL upstream repository SHALLOW at the parent commit,
# so the working tree ships the real bug: fpa2bv_converter::mk_fma() builds
# the h2 (second) rounding step's sticky reduction from sticky_h1 (the first
# step's discarded-bit range) instead of sticky_h2, so some inexact binary16
# fp.fma results round one ulp away from the true IEEE 754 encoding. For a
# fully pinned half-precision query the parent answers `sat` (wrong) where
# the operands determine the result and the answer must be `unsat`. The
# project's own regression test for the bug (the block the fix commit adds to
# src/test/smt_context.cpp) is extracted from the FIX commit at build time
# into /opt/golden (sha256-pinned); it is never part of this task tree and
# the fix commit is never reachable from /app/src.
#
# Toolchain: apt g++ (13), cmake (3.28), make on bench-base:ubuntu-24.04 -
# the same line the project's own build instructions use; apt packages are
# deliberately not version-pinned in this suite. The warm layer configures a
# Release build of both the shell target (z3 binary) and the project's unit
# test harness (test-z3) as uid 1000, so every later step on 1 CPU is
# strictly incremental. Build-time smoke steps prove the image ships the
# failing state: (1) the pre-fix binary answers `sat` on the pinned repro,
# and (2) the golden regression test, planted and rebuilt, fails with an
# assertion violation at the parent commit (fail closed if the bug does not
# reproduce at these dependency versions); the tree is restored byte-exact
# afterwards.
ARG UPSTREAM_SHA_PARENT=e950cd371c3ca16823079feded145bc6ce3feb95
ARG UPSTREAM_SHA_FIX=8d32b2b02ab31c5cd293362866fa32f6eab75e09
ARG GOLDEN_SHA=b4fc0a18327fe9a85d41927b50417f319f256185b7d41f4e483a44fdcaacfd0a

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG GOLDEN_SHA

ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends g++ cmake make git \
 && rm -rf /var/lib/apt/lists/*

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

WORKDIR /app
COPY files/ /app/
RUN chmod a+rx /app/plant_golden.sh 2>/dev/null || true \
 && chmod a+rwX /app

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/Z3Prover/z3.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Extract the project's own regression test for this bug (the fix-commit
# version of src/test/smt_context.cpp, which keeps every pre-existing test
# and adds the regression block) into /opt/golden using a THROWAWAY clone
# that is deleted immediately afterwards, so upstream test bytes never land
# in this task tree and the fix commit never lands in /app/src. The file's
# sha256 is asserted so a moved or tampered commit fails closed; the block
# must contain the fused multiply-add regression query.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/Z3Prover/z3.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:src/test/smt_context.cpp > /opt/golden/smt_context.cpp \
 && test "$(sha256sum /opt/golden/smt_context.cpp | cut -d' ' -f1)" = "${GOLDEN_SHA}" \
 && grep -q "fp.fma RNE x y x" /opt/golden/smt_context.cpp \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# The image is built as root; the trial may run as root or as uid 1000 (user
# `ubuntu` already exists in the base image). Make the tree writable by uid
# 1000 and WARM every cache the trial needs AS that user, so every writable
# path is owned by uid 1000 from the start. The warm pass compiles the shell
# target (the z3 binary) and the project's unit test harness (test-z3) with
# the project's own cmake recipe; the trial may have no network, so this
# layer IS the warm cache and the agent's rebuild is strictly incremental.
RUN chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true
RUN su -s /bin/bash ubuntu -c 'cd /app/src && \
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release > /tmp/warm_cfg.log 2>&1 && \
    (cmake --build build --target shell -j$(( $(nproc) > 12 ? 12 : $(nproc) )) > /tmp/warm_shell.log 2>&1) && \
    (cmake --build build --target test-z3 -j$(( $(nproc) > 12 ? 12 : $(nproc) )) > /tmp/warm_test.log 2>&1)'; rc=$?; \
    tail -3 /tmp/warm_cfg.log; tail -2 /tmp/warm_shell.log; tail -2 /tmp/warm_test.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    test -x /app/src/build/z3 && echo "z3 binary built" || { echo "no z3 binary"; exit 1; }; \
    test -x /app/src/build/test-z3 && echo "test-z3 harness built" || { echo "no test-z3 binary"; exit 1; }

# Preserve a pristine copy of the PRE-FIX solver binary: the verifier runs
# the agent's own /app/reproduce.sh against this binary to prove the
# reproduction genuinely fails on the unpatched tree (this is the "pre-fix
# tree concept" -- the tree shipped at the parent commit -- observed as the
# binary built from it).
RUN mkdir -p /opt/pre-fix \
 && cp /app/src/build/z3 /opt/pre-fix/z3 \
 && chmod 755 /opt/pre-fix /opt/pre-fix/z3

# Smoke 1: the pre-fix binary answers `sat` on the mined repro (the bug is
# present in this image at these toolchain versions). The query is the exact
# regression shape of the golden test; it is deleted immediately afterwards
# and appears nowhere else in the image or the task tree.
RUN cat > /tmp/smoke_repro.smt2 <<'EOF'
(declare-const x (_ FloatingPoint 5 11))
(declare-const y (_ FloatingPoint 5 11))
(declare-const xb (_ BitVec 16))
(declare-const yb (_ BitVec 16))
(assert (= x ((_ to_fp 5 11) xb)))
(assert (= y ((_ to_fp 5 11) yb)))
(assert (= xb #b1000001111000111))
(assert (= yb #b0011110111000000))
(assert (not (= ((_ fp.to_ieee_bv 16) (fp.fma RNE x y x)) #x889b)))
(check-sat-using (then fpa2bv simplify bit-blast smt))
EOF
RUN /opt/pre-fix/z3 /tmp/smoke_repro.smt2 | grep -qx '^sat$' || { \
      echo "SMOKE 1 FAIL: pre-fix binary did not answer sat on the pinned repro"; \
      /opt/pre-fix/z3 /tmp/smoke_repro.smt2; exit 1; } \
 && rm -f /tmp/smoke_repro.smt2

# Smoke 2: prove the image ships the FAILING state with the project's own
# tooling. Plant the golden upstream regression test (the fix-commit version
# of src/test/smt_context.cpp), rebuild the harness incrementally, and
# require the test to FAIL with an assertion violation (the parent answers
# `sat` to a fully pinned query that must be `unsat`). If the pinned
# dependency versions do not reproduce the bug, this layer fails and the
# image is never built. Restore the tree to a pristine, exactly-parent state
# afterwards.
RUN su -s /bin/bash ubuntu -c 'set -e; cd /app/src; \
    bash /app/plant_golden.sh; \
    cmake --build build --target test-z3 -j$(nproc) > /tmp/smoke_build.log 2>&1; \
    if ./build/test-z3 smt_context > /tmp/smoke_run.log 2>&1; then \
        echo "SMOKE 2 FAIL: golden regression test PASSED at the parent commit (bug absent)"; \
        tail -20 /tmp/smoke_run.log; exit 1; \
    fi; \
    grep -q "ASSERTION VIOLATION" /tmp/smoke_run.log || { \
        echo "SMOKE 2 FAIL: no assertion violation in test output"; tail -20 /tmp/smoke_run.log; exit 1; }; \
    git checkout -- src/test/smt_context.cpp; \
    test -z "$(git status --porcelain)"; \
    rm -f build/src/test/CMakeFiles/test-z3.dir/smt_context.cpp.o; \
    cmake --build build --target test-z3 -j$(( $(nproc) > 12 ? 12 : $(nproc) )) > /tmp/smoke_restore.log 2>&1; \
    if ! ./build/test-z3 smt_context > /tmp/smoke_restore_run.log 2>&1 \
       || ! grep -q "PASS" /tmp/smoke_restore_run.log; then \
        echo "SMOKE 2 FAIL: parent smt_context module does not pass after restore"; \
        tail -20 /tmp/smoke_restore_run.log; exit 1; \
    fi'
RUN echo "SMOKE OK: bug reproduces at the parent commit inside this image (repro=sat, golden regression test fails)"

CMD ["/bin/bash"]