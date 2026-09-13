# chainplate-keel: syncthing/syncthing consistency checker rejects a directory
# index entry whose Size equals the fixed SyntheticDirectorySize constant,
# breaking mixed-version synchronization of directory entries (upstream issue
# #10743).
#
# The image clones syncthing/syncthing SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree), extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/, and overlays that fixed test file into the tree exactly as the
# mining reproduction did (`git show <fix>:lib/protocol/protocol_test.go` on
# top of the parent tree), so `go test ./lib/protocol/ -run TestCheckConsistency
# -v` fails inside the image with the mined symptom ("Unexpected error
# non-file type with nonzero size (want nil) for Directory{Name:\"foo\", ...}"
# as TestCheckConsistency rejects a directory whose size is 128). The fix
# commit is fetched only into a throwaway bare clone that is deleted, so it is
# never reachable from /app/src. syncthing/syncthing is not a Terminal-Bench
# 2.1 source repository (checked against specs/tb21_source_repositories.json).
#
# The Go toolchain (go1.27.1.linux-amd64, well above the go.mod toolchain
# line) is installed to /usr/local/go. The module source cache ($GOPATH) and
# the go test artifact cache ($GOCACHE) are redirected to /opt and pre-warmed
# as image layers, so the trial runs offline and the agent's edit-to-test
# cycle is a one-file incremental recompile. The build-time smoke run fails
# the image build if the mined failing state is not present.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=ee275fee65b37ea75802c8fc3c9decd5a66cb065
ARG FIX_SHA=f1d631d66e1c3101a8968e0713fac29e67329134

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain ----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Go toolchain, pinned tarball with exact sha256.
RUN curl -fsSL -o /tmp/go.tgz https://go.dev/dl/go1.27.1.linux-amd64.tar.gz \
 && test "$(sha256sum /tmp/go.tgz | cut -d' ' -f1)" = "63d339f0da5ab53635a56f2490a7984dfe12dfcff22ad749f63edaf590168445" \
 && mkdir -p /usr/local/go \
 && tar -C /usr/local/go --strip-components=1 -xzf /tmp/go.tgz \
 && rm /tmp/go.tgz \
 && ln -sf /usr/local/go/bin/go /usr/local/bin/go \
 && go version

ENV PATH=/usr/local/go/bin:/usr/local/bin:$PATH \
    GOPATH=/opt/gopath \
    GOCACHE=/opt/gocache

# ---- working clone: buggy parent commit, fix commit unreachable -------------
RUN git clone --depth 1 https://github.com/syncthing/syncthing.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin ee275fee65b37ea75802c8fc3c9decd5a66cb065 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/syncthing/syncthing.git \
 && git fetch --depth 1 origin f1d631d66e1c3101a8968e0713fac29e67329134 \
 && mkdir -p /opt/golden \
 && git show f1d631d66e1c3101a8968e0713fac29e67329134:lib/protocol/protocol_test.go \
      > /opt/golden/protocol_test.go \
 && test "$(sha256sum /opt/golden/protocol_test.go | cut -d' ' -f1)" = "ecd37d420e1e22c0bcf0e66666df00baad830c3e0e7b162196893949c0abb517" \
 && grep -q "func TestCheckConsistency" /opt/golden/protocol_test.go \
 && grep -q "directory with synthetic size" /opt/golden/protocol_test.go \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the fixed regression test into the working tree -----------------
RUN cp /opt/golden/protocol_test.go /app/src/lib/protocol/protocol_test.go \
 && cd /app/src \
 && test "$(git status --porcelain)" = " M lib/protocol/protocol_test.go"

# ---- pre-warm the module source cache and go test artifact cache -------------
# 1) a passing package test: fetches every go.sum-pinned dependency the
#    protocol package needs and compiles the package once (offline
#    thereafter);
# 2) the reproduction smoke run proves the mined failing state is what the
#    image ships (it must fail TestCheckConsistency with the non-file type
#    with nonzero size error, exactly as the mining run did).
RUN cd /app/src && go test ./lib/protocol/ -run TestBlockSize -v > /tmp/warm.log 2>&1 \
 && echo "warm run ok (exit 0)" && tail -3 /tmp/warm.log
RUN cd /app/src && (go test ./lib/protocol/ -run TestCheckConsistency -v > /tmp/repro.log 2>&1; \
    rc=$?; \
    echo "--- reproduction exit: $rc ---"; tail -8 /tmp/repro.log; \
    grep -q "non-file type with nonzero size" /tmp/repro.log && grep -q "want nil" /tmp/repro.log && [ "$rc" -ne 0 ]) \
    || { echo "SMOKE FAIL: the mined bug did not reproduce in this image"; exit 1; }

WORKDIR /app
# The build ran as root and the trial may run as another uid; everything the
# agent or the `go test` toolchain writes must be world-writable.
RUN chmod -R a+rwX /app /opt/gopath /opt/gocache /opt/golden

CMD ["/bin/bash"]