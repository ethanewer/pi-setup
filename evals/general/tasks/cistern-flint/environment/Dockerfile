# cistern-flint: prometheus relabel config loses explicit empty separator /
# replacement on YAML/JSON round-trip (issue #18653).
#
# The image shallow-clones prometheus/prometheus at the PARENT commit (the real
# upstream bug is present in the working tree) and extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository). The fix commit is
# a descendant of the parent, so it is NOT reachable from the depth-1 clone the
# agent works on: the working clone is detached onto the parent SHA and the
# fix commit's absence is asserted at build time (and again by the verifier at
# trial time). The extraction uses a throwaway bare clone that is deleted.
#
# The Go package-manager works "module aware" (go.mod / go.work at the repo
# root). Module downloads and compiled packages go to /opt/gocache, which is
# warmed by one full model/relabel test run at build time, so the offline trial
# never needs the network. go.mod pins go 1.25.8; the go 1.26.0 binary the
# mining phase validated is installed from go.dev at build time.
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=7d1195258cb1702d958361deab455059fdebc08e
ARG FIX_SHA=7450865dcd1f7a521b96c5c9dad01e5eb2c66be0

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves.
RUN git clone --depth 1 https://github.com/prometheus/prometheus.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/prometheus/prometheus.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:model/relabel/relabel_test.go > /opt/golden/relabel_test.go \
 && test -s /opt/golden/relabel_test.go \
 && grep -q "Explicit empty separator and replacement" /opt/golden/relabel_test.go \
 && grep -q "TestRegexp_JSONUnmarshalThenMarshal" /opt/golden/relabel_test.go \
 && cd / && rm -rf /tmp/fixsrc

# ---- go toolchain + build deps ---------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git ca-certificates curl \
 && curl -sL -o /tmp/go.tgz https://go.dev/dl/go1.26.0.linux-amd64.tar.gz \
 && tar -C /opt -xzf /tmp/go.tgz \
 && rm -f /tmp/go.tgz \
 && /opt/go/bin/go version

ENV PATH=/opt/go/bin:$PATH \
    GOCACHE=/opt/gocache/build \
    GOMODCACHE=/opt/gocache/mod \
    GOENV=off

# ---- warm every go cache at build time (trial is offline) -------------------
# Runs the package's own test suite once; green at the parent commit. Warms the
# module downloads and the compiled-package cache so the trial needs no network.
RUN mkdir -p /opt/gocache/build /opt/gocache/mod \
 && cd /app/src \
 && go test -v ./model/relabel \
 && chmod -R a+rwX /opt/gocache

WORKDIR /app
COPY files/ /app/

RUN chmod -R a+rwX /app /opt/golden \
 && chmod +x /app/probe_relabel.sh

CMD ["/bin/bash"]