# capstan-current: syncthing/syncthing UPnP control-URL handling crashes on a
# query-only location string (upstream issue #10834).
#
# The image clones syncthing/syncthing SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree), extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/, and overlays that fixed test file into the tree exactly as the
# mining reproduction did (`git show <fix>:lib/upnp/upnp_test.go` on top of the
# parent tree), so `go test ./lib/upnp/ -run TestControlURLParsingQueryOnly -v`
# crashes inside the image with the mined symptom ("panic: runtime error: index
# out of range [0] with length 0" in the UPnP URL handling). The fix commit is
# fetched only into a throwaway bare clone that is deleted, so it is never
# reachable from /app/src. syncthing/syncthing is not a Terminal-Bench 2.1
# source repository (checked against specs/tb21_source_repositories.json).
#
# The Go toolchain (go1.27.1.linux-amd64, above the go.mod toolchain line) is
# installed to /usr/local/go. The module source cache ($GOPATH, used for the
# go.sum-pinned dependency sources) and the go test artifact cache ($GOCACHE)
# are redirected to /opt and pre-warmed as image layers, so the trial runs
# offline and the agent's edit-to-test cycle is a one-file incremental
# recompile. Both caches and the source tree are made world-writable for
# whichever uid the trial uses. The build-time smoke run fails the image build
# if the mined failing state is not present.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=119d5e72efcf7d4c003664640ca0db6f472edfa4
ARG FIX_SHA=703b185982e5cdcff26a119bfa932165d60bda19

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
 && git fetch --depth 1 origin 119d5e72efcf7d4c003664640ca0db6f472edfa4 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/syncthing/syncthing.git \
 && git fetch --depth 1 origin 703b185982e5cdcff26a119bfa932165d60bda19 \
 && mkdir -p /opt/golden \
 && git show 703b185982e5cdcff26a119bfa932165d60bda19:lib/upnp/upnp_test.go \
      > /opt/golden/upnp_test.go \
 && test "$(sha256sum /opt/golden/upnp_test.go | cut -d' ' -f1)" = "6403e2fa74874b0068dcade649168b3bfe65f7209462a4a580870a65e5192ad8" \
 && grep -q "func TestControlURLParsingQueryOnly" /opt/golden/upnp_test.go \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the fixed regression test into the working tree -----------------
RUN cp /opt/golden/upnp_test.go /app/src/lib/upnp/upnp_test.go \
 && cd /app/src \
 && test "$(git status --porcelain)" = " M lib/upnp/upnp_test.go"

# ---- pre-warm the module source cache and go test artifact cache -------------
# 1) a passing package test: fetches every go.sum-pinned dependency the upnp
#    package needs and compiles it once (offline thereafter);
# 2) compile every other lib package once so an agent exploring wider suites
#    does not trip on the missing network (build failures of unrelated
#    packages are expected, e.g. lib/api needs generated assets; the point is
#    the dependency download and compile cache);
# 3) the reproduction smoke run proves the mined failing state is what the
#    image ships (it must crash with the index-out-of-range panic).
RUN cd /app/src && go test ./lib/upnp/ -run TestSoapFaultParsing -v > /tmp/warm.log 2>&1 \
 && echo "warm run ok (exit 0)" && tail -3 /tmp/warm.log
RUN cd /app/src && { go test github.com/syncthing/syncthing/lib/... -run __NO_SUCH_MATCH__ -v > /tmp/widewarm.log 2>&1 || true; } \
 && echo "wide warm done (exit ignored: no test matches a no-such filter; unrelated packages are expected not to build)" \
 && tail -2 /tmp/widewarm.log
RUN cd /app/src && (go test ./lib/upnp/ -run TestControlURLParsingQueryOnly -v > /tmp/repro.log 2>&1; \
    rc=$?; \
    echo "--- reproduction exit: $rc ---"; tail -8 /tmp/repro.log; \
    grep -q "index out of range" /tmp/repro.log && [ "$rc" -ne 0 ]) \
    || { echo "SMOKE FAIL: the mined bug did not reproduce in this image"; exit 1; }

WORKDIR /app
# The build ran as root and the trial may run as another uid; everything the
# agent or the `go test` toolchain writes must be world-writable.
RUN chmod -R a+rwX /app /opt/gopath /opt/gocache /opt/golden

CMD ["/bin/bash"]