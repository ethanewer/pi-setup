# brackish-deepwater: duckdb/duckdb — the parallel CSV reader double-counts
# rows at buffer boundaries when a file's lines end with the three-byte
# sequence CR CR LF ('\r\r\n'), so a parallel scan of a file returns more rows
# than the file contains while the sequential scan is correct (real upstream
# issue #25164, fixed by upstream commit 17b972423bc2ed597ab310c7b6369ff0949356ad).
#
# The image clones duckdb/duckdb and checks out upstream PARENT commit
# 916aeeb64b0bd2e0f172266ac485daa929a4af98 (the commit immediately before the
# fix), so the agent receives the real repository with the real bug still in
# it. The clone is created with `git init` plus a single
# `git fetch --depth 1 origin <parent-sha>`, detached there, so the ONLY commit
# object in /app/src/.git is the parent itself; the fix commit is never
# fetched into the working clone (asserted at build time with
# `! git cat-file -e` and `rev-list --all --count == 1`).
#
# The upstream regression test added by the fix commit
# (test/sql/copy/csv/parallel/test_rrrn_parallel.test) and its fixture
# (data/csv/test/rrrn_parallel_test.csv, a 10,001-line file whose lines all
# end in \r\r\n) are extracted from the fix commit in a throwaway bare clone
# that is deleted afterwards (so the fix bytes never land in /app/src/.git),
# sha256-verified against values I computed from the upstream repository, and
# overlaid into the working tree exactly where the fix intends them. The
# project's own test runner then fails on the regression test inside the
# image with the mined symptom (parallel read reports 10002 rows, sequential
# 10000; "test cases: 1 | 1 failed").
#
# The release engine and the unittest runner are pre-built as cached image
# layers (ninja -j24 at build time), so the agent's fix cycle is a
# single-file recompile plus a relink, measured at ~30 seconds on one CPU.
# A copy of the PRE-FIX engine (built at image build time, before any fix is
# possible) is kept at /opt/pre-fix/ so the verifier can demonstrate that the
# agent's reproduction and the hidden cases genuinely detect the bug on the
# pre-fix tree concept while passing on the repaired tree.
#
# The chown-free byte-cost rule from v42 applies: the a+rwX open of /app/src
# happens in the SAME RUN that produced the build outputs (a layer is written
# once), so no copy-on-write duplication of the ~1.2 GB tree; /app itself gets
# a one-line world-open so the trial (uid 1000) can write /app/repro.sh.
# duckdb/duckdb is not a Terminal-Bench 2.1 source repository (checked against
# specs/tb21_source_repositories.json) and the repository has no submodules.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

ARG UPSTREAM_SHA=916aeeb64b0bd2e0f172266ac485daa929a4af98
ARG FIX_SHA=17b972423bc2ed597ab310c7b6369ff0949356ad
ARG GOLDEN_SHA=53b2116b7db9ab2e6b4e2df763c2d5e407f3e15fad0a499d29e74ab558b9d277
ARG FIXTURE_SHA=4a1daa3ff6dcaaa639c81f710c934ae2b9c33ddef642510bc02c6ffabb99ed99

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
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test + fixture from the FIX commit ------
# Throwaway bare clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git, and the upstream bytes live only at /opt/golden/.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/duckdb/duckdb.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:test/sql/copy/csv/parallel/test_rrrn_parallel.test \
      > /opt/golden/test_rrrn_parallel.test \
 && git show ${FIX_SHA}:data/csv/test/rrrn_parallel_test.csv \
      > /opt/golden/rrrn_parallel_test.csv \
 && test "$(sha256sum /opt/golden/test_rrrn_parallel.test | cut -d' ' -f1)" = "${GOLDEN_SHA}" \
 && test "$(sha256sum /opt/golden/rrrn_parallel_test.csv | cut -d' ' -f1)" = "${FIXTURE_SHA}" \
 && grep -q "verify_parallelism" /opt/golden/test_rrrn_parallel.test \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the regression test and fixture into the working tree -----------
RUN mkdir -p /app/src/test/sql/copy/csv/parallel /app/src/data/csv/test \
 && cp /opt/golden/test_rrrn_parallel.test /app/src/test/sql/copy/csv/parallel/test_rrrn_parallel.test \
 && cp /opt/golden/rrrn_parallel_test.csv /app/src/data/csv/test/rrrn_parallel_test.csv

# ---- pre-build the release engine + unittest runner (cached layers) ----------
# The tree is opened a+rwX in the same RUN that created the build outputs, so
# no second copy of the tree exists in a later layer.
RUN cd /app/src \
 && cmake -G Ninja -B build/release -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_UNITTESTS=1 -DEXTENSION_STATIC_BUILD=1 -DBUILD_EXTENSIONS=core_functions \
 && ninja -C build/release -j24 \
 && chmod -R a+rwX /app/src

# ---- keep a copy of the PRE-FIX engine for the verifier's pre-fix checks -----
RUN mkdir -p /opt/pre-fix \
 && cp /app/src/build/release/duckdb /opt/pre-fix/duckdb

# ---- smoke test: the mined failing state must be what the image ships --------
RUN out=$(/app/src/build/release/duckdb -csv -c "PRAGMA verify_parallelism; SELECT (SELECT COUNT(*) FROM read_csv('/app/src/data/csv/test/rrrn_parallel_test.csv', auto_detect=false, header=true, delim=',', columns={'id':'BIGINT','val':'VARCHAR'}, strict_mode=false, ignore_errors=true, max_line_size=2048, buffer_size=4096, parallel=true)) AS pc, (SELECT COUNT(*) FROM read_csv('/app/src/data/csv/test/rrrn_parallel_test.csv', auto_detect=false, header=true, delim=',', columns={'id':'BIGINT','val':'VARCHAR'}, strict_mode=false, ignore_errors=true, max_line_size=2048, buffer_size=4096, parallel=false)) AS sc;"); \
    row=$(printf '%s' "$out" | grep -E '^[0-9]+\,[0-9]+$' | head -1); \
    [ "$row" = "10002,10000" ] || { echo "SMOKE FAIL: expected 10002,10000 got '$row'"; exit 1; }

# ---- the project's own golden test must FAIL at the parent (mined) -----------
RUN /app/src/build/release/test/unittest "test/sql/copy/csv/parallel/test_rrrn_parallel.test" > /tmp/golden.out 2>&1; \
    grep -qE "1 failed" /tmp/golden.out || { echo "SMOKE FAIL: golden did not fail at parent"; tail -20 /tmp/golden.out; exit 1; }

# ---- the trial user (uid 1000) must be able to write the /app deliverable ----
RUN chmod 777 /app

WORKDIR /app

CMD ["/bin/bash"]