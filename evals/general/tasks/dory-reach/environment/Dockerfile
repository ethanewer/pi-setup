# ---------------------------------------------------------------------------
# dory-reach: trivy reports PEP 621 pyproject.toml dependency names without
# PEP 503 normalization (upstream issue #11050).
#
# The image clones aquasecurity/trivy and checks out upstream PARENT commit
# 748a639b1d436a0566d325a4233ca13baf4cbd60 (the commit immediately before
# upstream commit 0012281c8a8adad2eff1889f12fe08a0ca5a7bfc fixed it), so the
# agent gets the real repository with the real bug still in it.
#
# The working tree is the PRISTINE parent: the parent's own test suite is
# green inside this image (asserted by the smoke step below), so no failing
# case is seeded and the agent must write its own failing reproduction (a
# declared deliverable) before fixing anything.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>`, detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. The golden regression data (the fix
# commit's pyproject_test.go and testdata/happy_v2.toml) and the pristine
# parent's pyproject.go are extracted into /opt/golden via a throwaway clone
# that is deleted, so the fix bytes never land in the working clone either.
#
# The go module and build caches are relocated from /root to a world-writable
# /opt/gocache and exported through GOMODCACHE/GOCACHE/GOPATH, so the cached
# dependency closure survives and `go test` runs fully offline for BOTH
# root and uid-1000 trials (verified: no downloads, exit 0, with
# `network_mode: none`). The working tree is chown'd to uid 1000 so the
# agent can edit it regardless of which uid the harness uses.
# ---------------------------------------------------------------------------
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=748a639b1d436a0566d325a4233ca13baf4cbd60
ARG FIX_SHA=0012281c8a8adad2eff1889f12fe08a0ca5a7bfc

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- Go 1.26.3 toolchain (the exact build the mining used) ------------------
# The go toolchain tarball ships the compiler plus the standard-library source
# tree under <prefix>/src; the build-constraints and testing stack read it
# from there, which is why GOROOT is /opt/go and why GOEXPERIMENT=jsonv2 and
# CGO_ENABLED=0 must be set (without them `go` cannot see its own stdlib src
# and aborts with "build constraints exclude all Go files in /opt/go/src/...").
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/go.tgz https://github.com/actions/go-versions/releases/download/1.26.3-25533533231/go-1.26.3-linux-x64.tar.gz \
 && mkdir -p /opt/go \
 && tar -xzf /tmp/go.tgz -C /opt/go --strip-components=1 \
 && rm /tmp/go.tgz \
 && test -x /opt/go/bin/go \
 && /opt/go/bin/go version

# Caches live under /opt/gocache (world-writable, works for root and uid 1000).
ENV PATH=/opt/go/bin:$PATH \
    CGO_ENABLED=0 \
    GOEXPERIMENT=jsonv2 \
    GOMODCACHE=/opt/gocache/gopath/pkg/mod \
    GOCACHE=/opt/gocache/gobuild \
    GOPATH=/opt/gocache/gopath \
    GOTELEMETRY=off
RUN mkdir -p /opt/gocache/gopath/pkg/mod /opt/gocache/gobuild \
 && chmod -R a+rwX /opt/gocache

# ---- working clone: buggy parent commit only, fix commit unreachable --------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/aquasecurity/trivy.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && chown -R 1000:1000 /app/src

# ---- extract the upstream regression test + pristine parent source ----------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes never enter this repository either; the golden
# files live only in the image at /opt/golden/.
RUN git clone --depth 1 --no-checkout https://github.com/aquasecurity/trivy.git /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:pkg/dependency/parser/python/pyproject/pyproject_test.go \
      > /opt/golden/pyproject_test.go \
 && git show ${FIX_SHA}:pkg/dependency/parser/python/pyproject/testdata/happy_v2.toml \
      > /opt/golden/happy_v2.toml \
 && git show ${UPSTREAM_SHA}:pkg/dependency/parser/python/pyproject/pyproject.go \
      > /opt/golden/parent_pyproject.go \
 && test -s /opt/golden/pyproject_test.go \
 && grep -q "ruamel-yaml" /opt/golden/pyproject_test.go \
 && grep -qF '"Flask(>=1.0,<2.0)"' /opt/golden/happy_v2.toml \
 && grep -qF 'typing_extensions>=4' /opt/golden/happy_v2.toml \
 && grep -q "Save only name" /opt/golden/parent_pyproject.go \
 && ! grep -qF "NormalizePkgName(strings.Fields(dep)[0], true)" /opt/golden/parent_pyproject.go \
 && cd / \
 && rm -rf /tmp/fixsrc

# ---- integrity anchors -------------------------------------------------------
# The verifier hardcodes the sha256 of the go toolchain binary and of the three
# golden files and refuses to run if they drift (a root trial can substitute
# /opt/go/bin/go for a stub that reports success, or tamper with the golden
# bytes the verifier relies on; that attack class was proven in review on the
# sibling task). Assert the same values here so the committed verifier
# constants and the image cannot silently disagree.
RUN test "$(sha256sum /opt/go/bin/go | cut -d' ' -f1)" = "d68b7abbc40d0844f673f6cf06ae3cded225c50437c6454fa37ef178d079fe65" \
 && test "$(sha256sum /opt/golden/pyproject_test.go | cut -d' ' -f1)" = "59557e13b0f9ee4b213812d08655950f5eb85b0995fdacc6cc6900bd5da7976f" \
 && test "$(sha256sum /opt/golden/happy_v2.toml | cut -d' ' -f1)" = "ed5f54e532046c9fe971672216521e73e92643430ba83a27d3ae3892455528ff" \
 && test "$(sha256sum /opt/golden/parent_pyproject.go | cut -d' ' -f1)" = "cd6e2b9b5e9358a2fd4a32b9b7934cbcf1a62ee938071213ec9772f1d36bf4da" \
 && echo "anchors: toolchain and golden hashes match the verifier constants"

# ---- warm the pinned dependency cache and prove the parent tree is green ----
# First `go test` resolves the transitive closure of the python parser scope
# from the repo's committed go.sum against proxy.golang.org and caches it in
# /opt/gocache; later runs are fully offline. The parent's own suite must be
# green (there is no seeded failure in this image), and a second run must hit
# the warm cache.
RUN cd /app/src \
 && go test -v -short ./pkg/dependency/parser/python/... > /tmp/smoke.log 2>&1 \
 && ! grep -q "FAIL" /tmp/smoke.log \
 && ! grep -q "panic:" /tmp/smoke.log \
 && go test -v -short ./pkg/dependency/parser/python/... > /tmp/smoke2.log 2>&1 \
 && grep -q "(cached)" /tmp/smoke2.log \
 && echo "smoke: parent python parser scope green, second run served from cache"

# ---- writable by uid 1000 trials as well as root trials ---------------------
# (ownership set in the checkout RUN above, so no second copy of the tree is
# stored in a later layer)

WORKDIR /app

CMD ["/bin/bash"]