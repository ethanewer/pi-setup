# berm-coaming: duckdb/duckdb — errors raised inside a `list_reduce` lambda
# surface as `INTERNAL Error: Scalar function "list_reduce" threw an execution
# error, but the function is not marked as fallible - the function must call
# SetFallible()` plus a stack trace, instead of the clean user-facing error
# the lambda actually raised (real upstream issue #24616, fixed upstream by
# commit cf77bda5a15e7d3c8c0222a31c9ad84eec77e6c5 — one line:
# `fun.SetFallible()` on the ListReduceFun registration).
#
# The image clones duckdb/duckdb and checks out PARENT commit
# c54cb2c29b2fda8c78d278e62629bce08291daad (the commit immediately before
# that fix) with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>`, detached there, so the ONLY commit in /app/src/.git is the
# parent itself; the fix commit is never fetched into the working clone
# (asserted at build time with `! git cat-file -e` and rev-list count 1).
#
# The upstream regression test added by the fix commit (the two trailing
# statement-error blocks of test/sql/function/list/lambdas/reduce.test) is
# extracted from the fix commit via a THROWAWAY bare clone that is deleted
# immediately afterwards, so the fix bytes never land in /app/src/.git. The
# copy shipped in the image has the issue reference stripped from its
# concluding comment, because the trial container has outbound network under
# current harness defaults and naming the issue would turn the task into a
# lookup. The golden file is kept ONLY at /opt/golden (harness-owned): it is
# NOT overlaid into the shipped tree, so the agent never reads the expected
# outputs before writing its own reproduction; the verifier plants it at
# reward time, sha256-verified against the pinned value.
#
# The release engine and the unittest runner are pre-built as cached image
# layers (ninja -j24 at build time), so the agent's fix cycle is a
# single-file recompile plus a relink, measured ~32 s on one CPU. A copy of
# the PRE-FIX engine (built at image build time, before any fix is possible)
# is kept at /opt/pre-fix/duckdb so the verifier can demonstrate that the
# agent's reproduction and the authored hidden cases genuinely detect the
# bug on the pre-fix tree concept while passing on the repaired tree.
#
# The byte-cost rule from the v4.2 wave applies: the tree is chowned to uid
# 1000 AND opened a+rwX in the SAME RUN that produced the build outputs (a
# layer is written once, so no copy-on-write duplication of the ~500 MB tree).
# Ownership 1000 is required, not cosmetic: the project's own post-build step
# (scripts/create_local_extension_repo.py) chmods freshly copied extension
# files under build/release/repository on EVERY incremental build, and a
# root-owned file there makes a uid-1000 trial's relink fail with EPERM. /app
# gets a one-line world-open so the trial (uid 1000) can write /app/repro.sh
# and /app/summary.md.
#
# duckdb/duckdb is not a Terminal-Bench 2.1 source repository (checked
# against specs/tb21_source_repositories.json) and the repository has no
# submodules, so there is no transitive forbidden fetch.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

ARG UPSTREAM_SHA=c54cb2c29b2fda8c78d278e62629bce08291daad
ARG FIX_SHA=cf77bda5a15e7d3c8c0222a31c9ad84eec77e6c5
ARG GOLDEN_SHA=cdbae1f393ed279bdf5c945e85c7f1d059228334e5d7944fee5369001a01778c

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain ----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends g++ gcc make cmake ninja-build python3 git \
 && rm -rf /var/lib/apt/lists/*

# ---- working clone: buggy parent commit only, fix commit unreachable ---------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/duckdb/duckdb.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && git -C /app/src remote remove origin \
 && git -C /app/src remote -v | grep -q . && exit 1 || true

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git, and upstream test bytes live only at /opt/golden.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/duckdb/duckdb.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:test/sql/function/list/lambdas/reduce.test \
      | sed 's/errors, not INTERNAL errors (#24616)/errors, not INTERNAL errors/' \
      > /opt/golden/reduce.test \
 && test "$(sha256sum /opt/golden/reduce.test | cut -d' ' -f1)" = "${GOLDEN_SHA}" \
 && grep -q "Invalid Input Error: test error" /opt/golden/reduce.test \
 && ! grep -q "24616" /opt/golden/reduce.test \
 && cd / \
 && rm -rf /tmp/fixsrc

# ---- pre-build the release engine + unittest runner (cached layers) ----------
# The tree is opened a+rwX in the SAME RUN that created the build outputs, so
# no second copy of the tree exists in a later layer.
RUN cd /app/src \
 && cmake -G Ninja -B build/release -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_UNITTESTS=1 -DEXTENSION_STATIC_BUILD=1 -DBUILD_EXTENSIONS=core_functions \
 && ninja -C build/release -j24 \
 && chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src

# ---- keep a copy of the PRE-FIX engine for the verifier's pre-fix checks -----
RUN mkdir -p /opt/pre-fix \
 && cp /app/src/build/release/duckdb /opt/pre-fix/duckdb

# ---- smoke: the mined failing state must be what the image ships -------------
# 1. the CLI reproduces the INTERNAL error from the entry's first sample
RUN out=$(/app/src/build/release/duckdb -c "SELECT list_reduce([1, 2], lambda x, y: error('test error'));" 2>&1); \
    { printf '%s\n' "$out" | grep -q "INTERNAL Error" && printf '%s\n' "$out" | grep -q "must call SetFallible()"; } \
      || { echo "SMOKE FAIL: parent engine does not reproduce the INTERNAL error"; printf '%s\n' "$out" | head -3; exit 1; }
# 2. the project's own golden regression test FAILS at the parent (mined)
# DUCKDB_TEST_TEMP_DIR_ROOT keeps the unittest's scratch root out of the shipped
# tree: a retained-on-failure temp dir left root-owned 0755 in /app/src would
# make the runner unusable for a uid-1000 trial (EACCES on mkdir).
RUN rm -f /app/src/test/sql/function/list/lambdas/reduce.test \
 && install -m 644 /opt/golden/reduce.test /app/src/test/sql/function/list/lambdas/reduce.test \
 && (cd /app/src && DUCKDB_TEST_TEMP_DIR_ROOT=/tmp/golden-smoke build/release/test/unittest "test/sql/function/list/lambdas/reduce.test" > /tmp/golden.out 2>&1 || true) \
 && { grep -qE "1 failed" /tmp/golden.out || { echo "SMOKE FAIL: golden did not fail at parent"; tail -10 /tmp/golden.out; exit 1; }; } \
 && git -C /app/src restore --worktree --source=HEAD -- test/sql/function/list/lambdas/reduce.test \
 && rm -rf /tmp/golden-smoke /tmp/golden-smoke-home /tmp/golden.out \
 && test -z "$(git -C /app/src status --porcelain)" \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! ls -d /app/src/duckdb_unittest_tempdir 2>/dev/null

# ---- the trial user (uid 1000) must be able to write the /app deliverables ----
RUN chmod 777 /app

WORKDIR /app

CMD ["/bin/bash"]