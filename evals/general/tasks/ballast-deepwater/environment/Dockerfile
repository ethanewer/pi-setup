# ballast-deepwater: duckdb/duckdb — subtracting an interval whose
# microseconds field is the minimum 64-bit signed integer from a TIME or
# TIMETZ value silently overflows (signed negation of INT64_MIN wraps), so
# the query returns a completely wrong time instead of an error. The same
# unchecked negation exists in Interval::Invert, which DATE/TIMESTAMP minus
# interval routes through.
#
# The image clones duckdb SHALLOW at the PARENT commit (the real upstream bug
# is present in the working tree), extracts the project's own regression test
# added by the FIX commit into /opt/golden/, and overlays that test into the
# tree exactly where the fix intends it (test/sql/types/
# test_interval_negation_overflow.test), so `build/release/test/unittest
# "test_interval_negation_overflow"` fails inside the image with the mined
# symptom (silently wrong TIME value instead of an out-of-range error). The
# fix commit is fetched only into a throwaway bare clone that is deleted, so
# it is never reachable from /app/src. duckdb/duckdb is not a Terminal-Bench
# 2.1 source repository (checked against specs/tb21_source_repositories.json)
# and the repository has no submodules to check.
#
# The release engine and the unittest runner are pre-built as cached image
# layers, so the agent's fix cycle is an incremental recompile of at most two
# source files plus a relink. The smoke-test layer at the end fails the image
# build if the mined failing state is not what ships.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

ARG UPSTREAM_SHA=8616efa9da9921b9111fe46373af7936a5d96d16
ARG FIX_SHA=b94555b59e58941bf42da1aeb8f3251850b85e8f
ARG GOLDEN_SHA=18eb13b803bdd798b6596f071743911136f090e4709779f8152797180ae3bc57

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain ----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends g++ gcc make cmake ninja-build python3 git \
 && rm -rf /var/lib/apt/lists/*

# ---- working clone: buggy parent commit, fix commit unreachable -------------
RUN git clone --depth 1 https://github.com/duckdb/duckdb.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 8616efa9da9921b9111fe46373af7936a5d96d16 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/duckdb/duckdb.git \
 && git fetch --depth 1 origin b94555b59e58941bf42da1aeb8f3251850b85e8f \
 && mkdir -p /opt/golden \
 && git show b94555b59e58941bf42da1aeb8f3251850b85e8f:test/sql/types/test_interval_negation_overflow.test \
      > /opt/golden/test_interval_negation_overflow.test \
 && test "$(sha256sum /opt/golden/test_interval_negation_overflow.test | cut -d' ' -f1)" = "$GOLDEN_SHA" \
 && grep -q "INT64_MIN" /opt/golden/test_interval_negation_overflow.test \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the regression test into the working tree -----------------------
RUN cp /opt/golden/test_interval_negation_overflow.test \
      /app/src/test/sql/types/test_interval_negation_overflow.test

# ---- pre-build the release engine + unittest runner (cached layers) ----------
RUN cd /app/src \
 && cmake -G Ninja -B build/release -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_UNITTESTS=1 -DEXTENSION_STATIC_BUILD=1 -DBUILD_EXTENSIONS=core_functions \
 && ninja -C build/release -j24

# ---- smoke test: the mined failing state must be what the image ships --------
RUN /app/src/build/release/duckdb -c \
      "SELECT TIME '12:00:00' - INTERVAL '-4611686018427387904 microseconds -4611686018427387904 microseconds';" \
      > /tmp/repro.out 2>&1; \
    grep -qE "07:59:05\.224192" /tmp/repro.out

WORKDIR /app

# The build above ran as root; open the tree for whichever uid the trial uses
# (the agent must edit sources and ninja must write objects).
RUN chmod -R a+rwX /app/src

CMD ["/bin/bash"]