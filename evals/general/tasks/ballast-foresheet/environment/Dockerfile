# ballast-foresheet: gohugoio/hugo default SSRF hardening is incomplete
# (upstream issue #15285, fix commit 24d5e42ffa33eebdf906c495713f0d2bae30c0cb).
#
# Three bug families live in the default security policy of Hugo's remote
# resource fetching, all in config/security:
#   1. the default deny rule for IP-literal hosts only matches a lowercase
#      scheme, so "HTTP://127.0.0.1/" (mixed-case scheme) is allowed;
#   2. a resolved destination address is only gated on
#      IsGlobalUnicast()/IsPrivate(), so CGNAT (100.64.0.0/10), TEST-NET,
#      benchmarking, reserved and IETF-assignment IPv4 ranges, 2001:db8::/32
#      and 3fff::/20 documentation IPv6, and NAT64 prefixes that embed a
#      private IPv4 address all pass as "public";
#   3. IPv4-mapped IPv6 forms of those addresses also pass.
# The remote-fetch dial hook then connects to loopback/private/special
# addresses the policy promised to block.
#
# The image clones gohugoio/hugo SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree), extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/, and overlays the fixed test file into the tree exactly as the
# mining reproduction did (`git checkout <fix> -- config/security/
# securityConfig_test.go`). Running the golden tests inside the image then
# fails with the mined symptom (HTTP://127.0.0.1/ and 100.64.0.1:80 denied-
# cases get nil errors). The fix commit is fetched only into a throwaway bare
# clone that is deleted afterwards, so it is never reachable from /app/src.
#
# go1.27.1 is pinned (go.mod requires go 1.27.0). The module cache and the
# compiled package are warmed as cached image layers; the smoke run proves the
# mined failing state is what the image ships. Hugo is not a Terminal-Bench
# 2.1 source repository (checked against specs/tb21_source_repositories.json).
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain ---------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git curl \
 && rm -rf /var/lib/apt/lists/*

# Go 1.27.1, pinned (verified reachable: go.dev/dl).
RUN curl -fsSL -o /tmp/go.tgz https://go.dev/dl/go1.27.1.linux-amd64.tar.gz \
 && tar -C /usr/local -xzf /tmp/go.tgz \
 && rm /tmp/go.tgz \
 && /usr/local/go/bin/go version

# Go environment for the trial: no network, so nothing may be fetched at run
# time; the module cache (GOMODCACHE under GOPATH) and build cache are warmed
# by the build steps below. GOTOOLCHAIN=local forbids toolchain downloads and
# GOPATH points at /go so the caches stay writable for any trial uid.
ENV PATH=/usr/local/go/bin:$PATH \
    GOPROXY=off \
    GOTOOLCHAIN=local \
    GOPATH=/go \
    GOCACHE=/go/buildcache

# ---- working clone pinned to the PARENT (buggy) commit ----------------------
# The fix commit must not be reachable here: it is fetched only in a throwaway
# clone used to extract the golden regression test, then deleted.
RUN git clone --depth 1 https://github.com/gohugoio/hugo.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 5f0d88b8a3652bbee992f4cbba2b018527f16a15 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "5f0d88b8a3652bbee992f4cbba2b018527f16a15" \
 && ! git cat-file -e "24d5e42ffa33eebdf906c495713f0d2bae30c0cb^{commit}"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/gohugoio/hugo.git \
 && git fetch --depth 1 origin 24d5e42ffa33eebdf906c495713f0d2bae30c0cb \
 && mkdir -p /opt/golden \
 && git show 24d5e42ffa33eebdf906c495713f0d2bae30c0cb:config/security/securityConfig_test.go \
      > /opt/golden/securityConfig_test.go \
 && test "$(sha256sum /opt/golden/securityConfig_test.go | cut -d' ' -f1)" \
      = "85e6b0f79e2978f3555c2b14c1b4d35b3fbbc1e6f70d719fb21e94b87fd8ec1e" \
 && grep -q "TestCheckAllowedHTTPAddress" /opt/golden/securityConfig_test.go \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the golden regression test into the working tree ---------------
# Exactly what the mining reproduction did; the image now ships the failing
# state: running the golden tests fails with the mined symptom.
RUN cp /opt/golden/securityConfig_test.go /app/src/config/security/securityConfig_test.go

# ---- warm the Go caches and prove the failing state is shipped --------------
# The run below downloads (over the build-time network) and compiles exactly
# the packages the agent and the verifier will later build. It must FAIL with
# the mined symptom; the guard below asserts that failure is present.
RUN cd /app/src \
 && (GOPROXY=https://proxy.golang.org go test -vet=off ./config/security \
       -run 'TestCheckAllowedHTTPURLHardenedDefaultsIssue14792|TestCheckAllowedHTTPAddress' \
       -count=1 -v > /tmp/smoke.log 2>&1; true) \
 && grep -qF -- '--- FAIL: TestCheckAllowedHTTPURLHardenedDefaultsIssue14792' /tmp/smoke.log \
 && grep -qF -- '--- FAIL: TestCheckAllowedHTTPAddress' /tmp/smoke.log \
 && grep -qF 'HTTP://127.0.0.1/' /tmp/smoke.log \
 && grep -qF '100.64.0.1:80' /tmp/smoke.log

# The trial runs with no network and possibly as uid 1000; make the tree and
# the Go caches (module cache under /go/pkg/mod, build cache under GOCACHE)
# writable for whichever uid the harness uses.
RUN chmod -R a+rwX /go \
 && chmod -R a+rwX /app/src

WORKDIR /app

CMD ["/bin/bash"]