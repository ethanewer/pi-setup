# flotsam-fairway: duckdb/duckdb — printf('%c', 255) writes the raw low byte
# of a codepoint above 127 into the result, producing a VARCHAR that is not
# valid UTF-8. Displaying such a value raises a low-level decoding error
# ("invalid lead byte detected in Utf8Proc::UTF8ToCodepoint"), and any string
# function applied to the result (lower/upper/trim/reverse/...) throws an
# INTERNAL Error plus a stack trace (strip_accents even segfaults).
#
# Real upstream issue duckdb/duckdb#25166, fixed upstream by commit
# 02f7eeb4dbc8f36c3ac3dec7132a262dbe769e35 with parent
# e0b375a9a0d52c40803e989ca030d05c99d56299 (the mined failing state). The
# image clones duckdb SHALLOW at the PARENT commit, so the agent gets the real
# repository with the real bug still in it. The clone is created with `git
# init` + a single `git fetch --depth 1 origin <parent-sha>` and detached
# there, so the ONLY commit object in the /app/src object store is the parent
# itself: the fix commit and all later history are unreachable from it.
#
# The project's own regression test for this bug (the four "%c writes a single
# raw byte" blocks that upstream added to test/sql/function/string/
# test_printf.test) is extracted from the FIX commit in a throwaway bare clone
# that is deleted afterwards and stored at /opt/golden/. The working tree
# keeps the pinned parent's version of test_printf.test (which the buggy
# engine passes), so nothing in the trial hands the agent the expected
# behaviour; the verifier copies /opt/golden/test_printf.test over the tree's
# copy at verify time, because the unittest runner reads .test file content
# from the tree at runtime while its path list is baked at build time (verified
# empirically during authoring). The smoke layer proves the golden FAILS on the
# buggy engine, then restores the parent's version.
#
# The release engine and the unittest runner are pre-built as cached image
# layers (ninja -j24 at build time, measured 135s); a source edit triggers an
# incremental recompile of one file plus relinks, measured 25s at one CPU. A
# copy of the pre-fix CLI binary is preserved at /opt/pristine/duckdb for the
# verifier's pre-fix reproduction leg.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

ARG UPSTREAM_SHA=e0b375a9a0d52c40803e989ca030d05c99d56299
ARG FIX_SHA=02f7eeb4dbc8f36c3ac3dec7132a262dbe769e35
ARG GOLDEN_SHA=b38d0fd2a2cecf1eb527575effcad0b3b883f9797818b1fff09349db5a7500ed
ARG GOLDEN_PARENT_SHA=15ad830b6f3673753929359e284626672ad23dc4fdf66a90fe4a05ba5d110b5c

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

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git, and the upstream test bytes live only in the image at
# /opt/golden/ (never in this repository's tree). Also snapshot the pinned
# parent's version of the same file so the smoke layer can restore it.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/duckdb/duckdb.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:test/sql/function/string/test_printf.test \
      > /opt/golden/test_printf.test \
 && test "$(sha256sum /opt/golden/test_printf.test | cut -d' ' -f1)" = "${GOLDEN_SHA}" \
 && grep -q "Invalid UTF8 produced by format string" /opt/golden/test_printf.test \
 && cp /app/src/test/sql/function/string/test_printf.test /opt/golden/test_printf.parent.test \
 && test "$(sha256sum /opt/golden/test_printf.parent.test | cut -d' ' -f1)" = "${GOLDEN_PARENT_SHA}" \
 && cd / && rm -rf /tmp/fixsrc

# ---- pre-build the release engine + unittest runner (cached layers) -----------
RUN cd /app/src \
 && cmake -G Ninja -B build/release -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_UNITTESTS=1 -DEXTENSION_STATIC_BUILD=1 -DBUILD_EXTENSIONS=core_functions \
 && ninja -C build/release -j24

# ---- preserve the pre-fix CLI binary for the verifier's pre-fix leg -----------
RUN mkdir -p /opt/pristine \
 && cp /app/src/build/release/duckdb /opt/pristine/duckdb \
 && /opt/pristine/duckdb -c "SELECT printf('%c', 255);" 2>&1 \
      | grep -q "invalid lead byte detected"

# ---- smoke test: the mined failing state must be what the image ships ---------
# 1) The fix-commit regression test must FAIL against the buggy engine. The
#    runner reads the tree's .test content at runtime, so overlay the golden
#    copy, run, then restore the pinned parent's version (and re-hash).
# 2) The CLI reproductions must show the mined failures: the plain query fails
#    with the low-level decoding error and lower() throws an INTERNAL error.
RUN cd /app/src \
 && cp /opt/golden/test_printf.test test/sql/function/string/test_printf.test \
 && ( build/release/test/unittest "test/sql/function/string/test_printf.test" \
      > /tmp/gsmoke.out 2>&1 || true ) \
 && ! grep -q "All tests passed" /tmp/gsmoke.out \
 && grep -qE "Query unexpectedly succeeded|Invalid unicode" /tmp/gsmoke.out \
 && cp /opt/golden/test_printf.parent.test test/sql/function/string/test_printf.test \
 && test "$(sha256sum test/sql/function/string/test_printf.test | cut -d' ' -f1)" = "${GOLDEN_PARENT_SHA}" \
 && build/release/duckdb -c "SELECT printf('%c', 255);" 2>&1 \
      | grep -q "invalid lead byte detected" \
 && build/release/duckdb -c "SELECT lower(printf('%c', 255));" 2>&1 \
      | grep -q "INTERNAL Error" \
 && chmod -R a+rwX /app/src

WORKDIR /app

# The ownership change above is inside the smoke RUN so the tree is copied
# into only ONE image layer (a separate `chmod -R` RUN would duplicate the
# whole 1.2 GB /app/src, including build/release, into a second layer). The
# golden and pristine snapshots stay root-owned and non-writable by the trial
# uid; the verifier re-pins their integrity at verify time.

CMD ["/bin/bash"]