# ---------------------------------------------------------------------------
# ballast-chartroom: trivy's conda environment parser panics on an
# operator-only dependency line (upstream issue #10955).
#
# The image clones aquasecurity/trivy and checks out upstream PARENT commit
# 3dc5f8768b343a07694ba1cc09425f485d4c1b0f (the commit immediately before
# upstream commit f964fa2bb61e1b59088d2b35397ca8fd39045b00 fixed it), so the
# agent gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>`, detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. The golden regression test is extracted
# from the fix commit into /opt/golden via a throwaway clone that is deleted,
# so the fix bytes never land in the working clone either.
#
# The mined reproduction state is then overlaid into the working tree: the
# fix commit's parse_test.go plus testdata/operator-only-dep.yaml replace the
# parent's versions, exactly as the mining reproduction did. `go test` on the
# conda parser scope then fails inside the image with the mined symptom
# (`panic: runtime error: index out of range [0] with length 0`), which the
# smoke build asserts before shipping.
# ---------------------------------------------------------------------------
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=3dc5f8768b343a07694ba1cc09425f485d4c1b0f
ARG FIX_SHA=f964fa2bb61e1b59088d2b35397ca8fd39045b00

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

ENV PATH=/opt/go/bin:$PATH \
    CGO_ENABLED=0 \
    GOEXPERIMENT=jsonv2

# ---- working clone: buggy parent commit only, fix commit unreachable --------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/aquasecurity/trivy.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes never enter this repository either; the golden
# files live only in the image at /opt/golden/.
RUN git clone --depth 1 --no-checkout https://github.com/aquasecurity/trivy.git /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:pkg/dependency/parser/conda/environment/parse_test.go \
      > /opt/golden/parse_test.go \
 && git show ${FIX_SHA}:pkg/dependency/parser/conda/environment/testdata/operator-only-dep.yaml \
      > /opt/golden/operator-only-dep.yaml \
 && test -s /opt/golden/parse_test.go \
 && grep -q "dependency line contains only operators" /opt/golden/parse_test.go \
 && grep -qF '  - "="' /opt/golden/operator-only-dep.yaml \
 && grep -qF '  - "=="' /opt/golden/operator-only-dep.yaml \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the corrected regression data into the working tree ------------
# This is exactly the state the mining reproduction used: parent tree + the
# fix commit's test file and fixture. The new fixture lands as an untracked
# file, and parse_test.go shows as modified, both expected states.
RUN cp /opt/golden/parse_test.go /app/src/pkg/dependency/parser/conda/environment/parse_test.go \
 && cp /opt/golden/operator-only-dep.yaml /app/src/pkg/dependency/parser/conda/environment/testdata/operator-only-dep.yaml

# ---- integrity anchors -------------------------------------------------------
# The verifier hardcodes the sha256 of the go toolchain binary and of the two
# golden regression files and refuses to run if they drift (a root trial can
# substitute /opt/go/bin/go for a stub that reports success; proven in review
# before this hardening). Assert the same values here so the committed
# verifier constants and the image cannot silently disagree: this build step
# fails loudly if the pinned tarball or the golden extraction ever changes
# their bytes.
RUN test "$(sha256sum /opt/go/bin/go | cut -d' ' -f1)" = "d68b7abbc40d0844f673f6cf06ae3cded225c50437c6454fa37ef178d079fe65" \
 && test "$(sha256sum /opt/golden/parse_test.go | cut -d' ' -f1)" = "a4f841e7ad2e0d305c282a34867112a85d6e88e3e4306c7b78decbcb1ba69fb6" \
 && test "$(sha256sum /opt/golden/operator-only-dep.yaml | cut -d' ' -f1)" = "276da5f56f15a95dbed6a633f5d9a579bfed578f7e4f00cc6ba46cb4ef3e25f1" \
 && echo "anchors: toolchain and golden hashes match the verifier constants"

# ---- warm the pinned dependency cache and prove the mined failing state -----
# First `go test` resolves the transitive closure of the conda parser scope
# from the repo's committed go.sum against proxy.golang.org and caches it in
# /root/go; later runs are fully offline. The smoke run must show the panic.
RUN cd /app/src \
 && (go test -v -short ./pkg/dependency/parser/conda/... > /tmp/smoke.log 2>&1 || true) \
 && grep -qF "index out of range [0] with length 0" /tmp/smoke.log \
 && grep -q "FAIL" /tmp/smoke.log \
 && echo "smoke: conda parser scope reproduces the mined panic"

WORKDIR /app

CMD ["/bin/bash"]