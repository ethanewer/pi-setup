ARG UPSTREAM_SHA_PARENT=5fcd89bf8c4f37141f5f31a6bfc05b89f55d7e4d
ARG UPSTREAM_SHA_FIX=8fd4b73ab5359395965311b0bb275fe78a2da9b0

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Toolchain for the Z3 cmake build (C++17/C++23 sources need the g++ 13
# line that Ubuntu 24.04 ships; the ubuntu-22.04 g++ 11 cannot compile this
# tree). Built at image-build time; the trial itself has no network.
RUN apt-get update \
 && apt-get install -y --no-install-recommends g++ cmake make git \
 && rm -rf /var/lib/apt/lists/*

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

# Extract the project's OWN regression test file for this bug (the test that
# the fix commit extends, src/test/seq_rewriter.cpp) into /opt/golden using
# a THROWAWAY clone that is deleted immediately afterwards, so upstream test
# bytes never land in this task tree and the fix commit never lands in
# /app/src.
#
# The test's answer-bearing comments are stripped before baking the file in.
# The unmodified fix-commit file documents the issue number and describes the
# fixed function and the exact offset-tracking mechanism in prose; the trial
# container runs as root and trials have network egress, so leaving that text
# readable at /opt/golden hands the agent the solution (the instruction even
# mentions the path). Only comment lines are removed -- every code line stays
# byte-identical, so the planted module compiles and runs exactly as upstream.
RUN git init -q /tmp/z3-fix-clone \
 && cd /tmp/z3-fix-clone \
 && git remote add origin https://github.com/Z3Prover/z3.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:src/test/seq_rewriter.cpp > /opt/golden/seq_rewriter.cpp \
 && test -s /opt/golden/seq_rewriter.cpp \
 && awk '\
function flush() { if (have_prev) { print prev; have_prev = 0 } }\
/27\. Solver: seq\.nth_i on a concat with an ite/ { skip = 2; next }\
skip > 0 { skip--; next }\
have_prev && /\/\/ 27\. Regression for a refutational soundness bug/ { prev = ""; have_prev = 0; in27 = 1; next }\
in27 { if ($0 ~ /^[ \t]*\/\/ -+[ \t]*$/) in27 = 0; next }\
{ flush(); prev = $0; have_prev = 1 }\
END { flush() }\
' /opt/golden/seq_rewriter.cpp > /opt/golden/tmp.cpp \
 && mv /opt/golden/tmp.cpp /opt/golden/seq_rewriter.cpp \
 && test -s /opt/golden/seq_rewriter.cpp \
 && grep -q "self-referential seq.extract with ite branch sat" /opt/golden/seq_rewriter.cpp \
 && grep -q "tst_seq_rewriter: all tests passed" /opt/golden/seq_rewriter.cpp \
 && ! grep -qE "10621|mk_seq_nth_i|cumulative character position" /opt/golden/seq_rewriter.cpp \
 && cd / \
 && rm -rf /tmp/z3-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Warm the WHOLE build as an image layer: configure + full parallel Release
# build of the `shell` binary (build/z3) and the project's own test harness
# (build/test-z3) at the BUGGY parent commit. The trial has no network, so
# this layer IS the warm cache: after the agent edits sources, an
# incremental `cmake --build build --target shell` recompiles only the
# changed files and relinks in minutes at 1 vCPU (a from-scratch build at
# 1 CPU would be far too slow to attempt inside the trial).
RUN cd /app/src \
 && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build build --target shell test-z3 -j$(nproc) \
 && test -x build/z3 \
 && test -x build/test-z3 \
 && echo "warm-build-ok"

# The image is built as root; the trial may run as root or as uid 1000
# (user `ubuntu` already exists in the base image). Make the tree writable
# by uid 1000 from the start.
WORKDIR /app
RUN chmod -R a+rwX /app && chown -R 1000:1000 /app/src 2>/dev/null || true

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]