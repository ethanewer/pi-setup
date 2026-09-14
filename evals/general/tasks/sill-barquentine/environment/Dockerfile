# sill-barquentine: duckdb/duckdb issue #24602 -
# CREATE SEQUENCE with a NULL option value (START / START WITH / MINVALUE /
# MAXVALUE / INCREMENT BY) crashes the process with "INTERNAL Error: Calling
# GetValue on a value that is NULL" instead of a clean Parser Error. The task
# tree is the REAL upstream repository checked out at the PARENT commit of the
# fix; the fix commit itself is never fetched into /app/src.
ARG UPSTREAM_SHA_PARENT=b98263558bf0afb1f0eac0d559a0a6604bbd688c
ARG UPSTREAM_SHA_FIX=115e593139967b82764c5452540c955962033438

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Thread-pool pins: the trial runs at 1 CPU.
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 HOME=/home/duck

# Base tooling: git (for the clone), the C++ toolchain and ninja for the build.
# apt is deliberately not version-pinned in this suite.
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends g++ gcc make cmake ninja-build python3 git ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The fix
# commit (which an agent must not be able to look up, fetch or grep) is NEVER
# fetched into this clone; it is asserted unreachable below.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/duckdb/duckdb.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# Configure and build the project (CLI + the sqllogictest runner) so the
# agent's work is a small incremental ninja rebuild. Ownership is fixed in the
# SAME RUN that creates the files, so the ~2 GB build tree is not copied into
# a second image layer. A clean `git status` at the end proves the build
# writes nothing outside the (gitignored) build/ directory.
RUN cd /app/src \
 && cmake -G Ninja -B build/release -DCMAKE_BUILD_TYPE=Release -DBUILD_UNITTESTS=1 -DEXTENSION_STATIC_BUILD=1 -DBUILD_EXTENSIONS=core_functions \
 && ninja -C build/release \
 && mkdir -p /home/duck \
 && chown -R 1000:1000 /app/src /home/duck \
 && test -z "$(git status --porcelain)" \
 && test -x build/release/duckdb \
 && test -x build/release/test/unittest \
 && echo "warm build ok; tree clean"

# Pristine pre-fix copy of the source file the bug lives in, plus a pristine
# pre-fix build output (the "pre-fix tree concept" the verifier runs the
# agent's reproduction against). This is baked from the PARENT tree at image
# build time, BEFORE any fix can exist; nothing at verification time rebuilds
# it, because DuckDB's unity build records absolute /app/src include paths, so
# a copied tree cannot be rebuilt faithfully offline.
RUN mkdir -p /opt/prefix/bin /opt/prefix/tree/src/parser/peg/transformer /opt/prefix/tree/build/release \
 && git -C /app/src show ${UPSTREAM_SHA_PARENT}:src/parser/peg/transformer/transform_create_sequence.cpp \
      > /opt/prefix/tree/src/parser/peg/transformer/transform_create_sequence.cpp \
 && cp /app/src/build/release/duckdb /opt/prefix/bin/duckdb \
 && cp /app/src/build/release/duckdb /opt/prefix/tree/build/release/duckdb \
 && chmod 755 /opt/prefix/bin/duckdb /opt/prefix/tree/build/release/duckdb \
 && test -s /opt/prefix/tree/src/parser/peg/transformer/transform_create_sequence.cpp

# Extract the project's own regression test for this bug (the "NULL is not a
# valid value for sequence options" block that the fix commit added to
# test/sql/catalog/sequence/test_sequence.test) into /opt/golden using a
# THROWAWAY clone that is deleted immediately afterwards, so the fix commit
# never lands in /app/src and no upstream test bytes enter this task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/duckdb/duckdb.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:test/sql/catalog/sequence/test_sequence.test \
      > /opt/golden/test_sequence.test \
 && test -s /opt/golden/test_sequence.test \
 && grep -q "START value must not be NULL" /opt/golden/test_sequence.test \
 && wc -l /opt/golden/test_sequence.test \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone. The
# object store holds exactly one commit (the parent), so the commit object and
# every blob it introduced are absent.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# sha256 pins of the golden regression test, the pristine pre-fix source and
# the pristine pre-fix CLI binary, so the verifier can detect substitution.
# The same values are hardcoded in /tests/test.sh (mounted read-only), so
# rewriting /opt is not enough to pass.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/test_sequence.test | awk '{print $1 "  /opt/golden/test_sequence.test"}' > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/tree/src/parser/peg/transformer/transform_create_sequence.cpp | awk '{print $1 "  /opt/prefix/tree/src/parser/peg/transformer/transform_create_sequence.cpp"}' > /opt/pins/prefix-src.sha256 \
 && sha256sum /opt/prefix/bin/duckdb | awk '{print $1 "  /opt/prefix/bin/duckdb"}' > /opt/pins/prefix-cli.sha256 \
 && cat /opt/pins/golden.sha256 /opt/pins/prefix-src.sha256 /opt/pins/prefix-cli.sha256

COPY --chown=1000:1000 files/ /app/
# The trial user (uid 1000) writes its deliverables (/app/repro.sh,
# /app/summary.md) directly into /app, so the directory itself must be
# writable by uid 1000.
RUN chown 1000:1000 /app
WORKDIR /app
CMD ["/bin/bash"]