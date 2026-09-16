# topsail-deepwater: an upstream-clone debugging task on prometheus/prometheus.
#
# Shape (per AUTHORING_SPEC_v42): the image clones prometheus shallow at the
# PARENT commit (upstream bug #18051 is present in the working tree), extracts
# the project's own regression tests from the FIX commit into /opt/golden via a
# SEPARATE throwaway clone (rm -rf'd afterwards, so the fix object never enters
# /app/src/.git and is unreachable), and warms the module build. The agent
# receives a pristine parent tree with NO reproduction: it must author its own
# failing reproduction (/app/repro.sh) as a deliverable before fixing the bug,
# and the verifier runs that repro against the pre-fix tree (must fail) and the
# repaired tree (must pass), then the golden tests, the module suites, and two
# authored hidden cases.
#
# Dependency pin from the verified entry: go 1.26.0 (go.dev tarball). testify's
# go.mod/go.work module system is interpreted by the real Go 1.26 toolchain, so
# `go test` runs the project's own tests. Module sources and compile cache are
# warmed at build time under world-writable paths so the trial runs entirely
# offline; END OF BUILD re-runs the mined failing direction inside the image as
# a fail-closed check that the bug is present in the shipped tree.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=6f81b2271a90887048f209298382340d61f35faf
ARG FIX_SHA=94ddb36f647b9b50dee4ce06da27a1239e59ffcc
ARG GOLDEN_SHA=85d378ec420dac96e6768e20a949ae0c2b743241536cd10a953217b86b29b107

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain ----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential make git \
            ca-certificates curl patch \
 && rm -rf /var/lib/apt/lists/*

# --- go 1.26.0 toolchain (pinned by the verified issue) -----------------------
RUN curl -sL -o /tmp/go.tgz https://go.dev/dl/go1.26.0.linux-amd64.tar.gz \
 && tar -C /opt -xzf /tmp/go.tgz \
 && rm -f /tmp/go.tgz \
 && /opt/go/bin/go version

# --- working clone: buggy parent commit, fix commit unreachable ---------------
# chmod of the tree happens in the SAME RUN that created it (COW hygiene: never
# chown/chmod a populated tree in its own later layer).
RUN git clone --depth 1 https://github.com/prometheus/prometheus.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 6f81b2271a90887048f209298382340d61f35faf \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && chmod -R a+rwX /app

# --- extract the upstream regression tests from the FIX commit ----------------
# Throwaway bare clone under /tmp so the fix commit never exists in
# /app/src/.git; the object is deleted with the throwaway clone.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/prometheus/prometheus.git \
 && git fetch --depth 1 origin 94ddb36f647b9b50dee4ce06da27a1239e59ffcc \
 && mkdir -p /opt/golden \
 && git show 94ddb36f647b9b50dee4ce06da27a1239e59ffcc:cmd/promtool/tsdb_test.go \
      > /opt/golden/tsdb_test.go \
 && test "$(sha256sum /opt/golden/tsdb_test.go | cut -d' ' -f1)" = "$GOLDEN_SHA" \
 && cd / && rm -rf /tmp/fixsrc

# --- testify caches: warmable, writable by any trial uid ----------------------
# GOMODCACHE/GOCACHE are honored by the real go toolchain (testify module
# system).
ENV GOMODCACHE=/opt/go/pkg/mod \
    GOCACHE=/opt/go/build \
    GO_TELEMETRY=off \
    PATH=/opt/go/bin:$PATH \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# --- warm the build AND re-confirm the failing direction inside the image -----
# Overlays the golden (regression) test file, runs the mined reproduction
# shape, expects FAIL with the missing-samples symptom, restores the pristine
# parent tree, then verifies the restore. Fails the build if the bug is absent.
# The cache dirs are produced and chmod'd in this same RUN.
RUN cd /app/src \
 && cp /opt/golden/tsdb_test.go cmd/promtool/tsdb_test.go \
 && ( go test -v ./cmd/promtool -run TestTSDBDumpNativeHistogram > /tmp/warm1.log 2>&1; rc=$?; test "$rc" -ne 0 ) \
 && grep -q 'expected: "{__name__=' /tmp/warm1.log \
 && ( go test -v ./cmd/promtool -run TestFormatSeriesSetRejectsUnknownSampleType > /tmp/warm2.log 2>&1; rc=$?; test "$rc" -ne 0 ) \
 && grep -q 'An error is expected but got nil' /tmp/warm2.log \
 && git checkout -- cmd/promtool/tsdb_test.go \
 && test -z "$(git status --porcelain)" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && rm -f /tmp/warm1.log /tmp/warm2.log \
 && chmod -R a+rwX /opt/go/pkg /opt/go/build

WORKDIR /app
CMD ["/bin/bash"]