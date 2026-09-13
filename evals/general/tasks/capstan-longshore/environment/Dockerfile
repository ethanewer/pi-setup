# ---------------------------------------------------------------------------
# capstan-longshore: duckdb/duckdb reports the missing named parameters of an
# EXECUTE in hash-map iteration order instead of declaration order (real
# upstream issue #25299).
#
# The image clones duckdb/duckdb and checks out upstream PARENT commit
# 9c21294d984dfe9a1da5d055b5fce3e8a0d634b2 (immediately before upstream commit
# c306b47b18095823f22774a972e7cda1170f87a0 fixed issue #25299), so the agent
# gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. The golden regression test file is
# extracted from the fix commit in a throwaway bare clone that is deleted, so
# the fix bytes never land in the working clone either. The golden copy is
# overlaid into the tree exactly where the fix intends it
# (test/sql/prepared/prepared_named_param.test), so the project's own test
# runner fails on it inside the image with the mined symptom.
#
# The release engine and the unittest runner are pre-built as cached image
# layers (`ninja -j24` at build time), so the agent's fix cycle is an
# incremental recompile plus a relink, on the order of 15-20 minutes at one
# CPU. The smoke-test layer at the end fails the image build if the mined
# failing state is not what ships.
# ---------------------------------------------------------------------------
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

ARG UPSTREAM_SHA=9c21294d984dfe9a1da5d055b5fce3e8a0d634b2
ARG FIX_SHA=c306b47b18095823f22774a972e7cda1170f87a0
ARG GOLDEN_SHA=14da4c35447fb14b92f616ef5356a316f55365505a286647a2f1171f99f7a928

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

# ---- extract the upstream regression test from the FIX commit -----------------
# Throwaway bare clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git, and the upstream test bytes live only in the image at
# /opt/golden/ (never in this repository's tree).
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/duckdb/duckdb.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:test/sql/prepared/prepared_named_param.test \
      > /opt/golden/prepared_named_param.test \
 && test "$(sha256sum /opt/golden/prepared_named_param.test | cut -d' ' -f1)" = "${GOLDEN_SHA}" \
 && grep -q "prepare q03 as select" /opt/golden/prepared_named_param.test \
 && grep -q "cc, dd, ee" /opt/golden/prepared_named_param.test \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the regression test into the working tree ------------------------
RUN cp /opt/golden/prepared_named_param.test \
      /app/src/test/sql/prepared/prepared_named_param.test

# ---- pre-build the release engine + unittest runner (cached layers) -----------
RUN cd /app/src \
 && cmake -G Ninja -B build/release -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_UNITTESTS=1 -DEXTENSION_STATIC_BUILD=1 -DBUILD_EXTENSIONS=core_functions \
 && ninja -C build/release -j24

# ---- smoke test: the mined failing state must be what the image ships ---------
# The overlaid regression test must FAIL on the buggy engine (the q03 block
# expects "cc, dd, ee" but the engine prints the hash-order "ee, cc, dd"), and
# the issue's own CLI reproduction must print exactly that hash order.
RUN cd /app/src \
 && (./build/release/test/unittest "test/sql/prepared/prepared_named_param.test" > /tmp/gsmoke.out 2>&1 || true) \
 && grep -q "cc, dd, ee" /tmp/gsmoke.out \
 && grep -q "ee, cc, dd" /tmp/gsmoke.out \
 && grep -q "FAILED" /tmp/gsmoke.out \
 && ! grep -q "All tests passed" /tmp/gsmoke.out \
 && ./build/release/duckdb -c 'PREPARE q03 AS SELECT $aa, $bb, $cc, $dd, $ee; EXECUTE q03(aa := 1, bb := 2);' 2>&1 \
      | grep -q "parameters: ee, cc, dd"

WORKDIR /app

# The build above ran as root; open the tree for whichever uid the trial uses
# (the agent must edit sources and ninja must write objects).
RUN chmod -R a+rwX /app/src && chmod a+rwX /app

CMD ["/bin/bash"]