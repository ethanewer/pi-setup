# yaw-roadstead: spf13/cobra YAML see_also entries for nested subcommands
# carry only the bare leaf name instead of the full command path (upstream
# issue #1771).
#
# The image clones spf13/cobra SHALLOW at the PARENT commit
# (6bf8cd85825800c5cbc63009b1fb2c54185f05ed, immediately before fix
# 7790bf97fd40e285913066cf65387ad281cd6c2e), so the agent gets the real
# tree with the real bug in it. The fix commit is fetched only into a
# THROWAWAY clone that is deleted after the golden regression test
# (doc/yaml_docs_test.go from the fix commit) is extracted to /opt/golden;
# the fix object is never reachable from /app/src, and the object store of
# /app/src holds exactly one commit (`git rev-list --all --count` == 1).
#
# The Go 1.24.0 toolchain tarball from go.dev/dl is version-pinned, and the
# golang module dependencies (pflag v1.0.5, yaml.v2 v2.4.0, mousetrap
# v1.0.1, go-md2man v2.0.2, blackfriday v2.1.0, check.v1) are locked by the
# repo's committed go.sum, which `go get` verifies; both the module cache
# and the compile cache are warmed into the image as user `ubuntu`, so
# `go get`/`go test` work offline in seconds at trial time.
#
# A build-time smoke run proves the shipped state both ways in scratch
# copies: with the golden test overlaid the suite fails exactly as mined
# (--- FAIL: TestGenYamlDoc, `Expected to contain` a full command path),
# and after applying the one-line fix it passes. The scratch copies are
# deleted; /app/src is left pristine at the parent commit.
#
# spf13/cobra and every golang module it depends on were checked against
# specs/tb21_source_repositories.json (68 repositories the frozen
# Terminal-Bench 2.1 reference uses): no overlap, so the disjointness gate
# is satisfied. The trial runs as uid 1000 (USER ubuntu + [agent]/[verifier]
# user="ubuntu"), and /opt/go stays root-owned so the toolchain cannot be
# substituted.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=6bf8cd85825800c5cbc63009b1fb2c54185f05ed
ARG FIX_SHA=7790bf97fd40e285913066cf65387ad281cd6c2e

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- toolchain ----------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/go.tgz https://go.dev/dl/go1.24.0.linux-amd64.tar.gz \
 && tar xzf /tmp/go.tgz -C /opt \
 && /opt/go/bin/go version \
 && rm -f /tmp/go.tgz

# ---- working clone: buggy parent commit only, fix commit unreachable -------
# git init + one depth-1 fetch of the pinned SHA: the object store holds
# exactly the parent commit, so neither the fix nor any later history is
# reachable from /app/src. The tree is handed to uid 1000 in the same RUN
# that produced it (no copy-on-write duplication of layers).
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/spf13/cobra.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && test "$(git rev-list --all --count)" = "1" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src' \
 && chown -R 1000:1000 /app/src

# ---- extract the upstream regression test from the fix commit ----------------
# Throwaway bare clone, deleted afterwards: the fix commit never enters
# /app/src and the upstream test bytes never enter this task tree. /opt/golden
# is then root-owned and read-only so the unprivileged trial user cannot
# substitute it.
RUN git init -q /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/spf13/cobra.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$FIX_SHA" \
 && mkdir -p /opt/golden \
 && cp doc/yaml_docs_test.go /opt/golden/yaml_docs_test.go \
 && grep -q "echoSubCmd.CommandPath()" /opt/golden/yaml_docs_test.go \
 && test -n "$(git show ${FIX_SHA}:doc/yaml_docs.go | grep -c 'child.CommandPath()')" \
 && cd / \
 && rm -rf /tmp/fixsrc

# ---- belt: the fix commit must be unreachable from the working clone --------
RUN cd /app/src \
 && if git cat-file -e ${FIX_SHA}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && test "$(git rev-list --all --count)" = "1"

# ---- warm the module + compile caches as the trial user (offline trial) -----
# go get downloads the go.sum-locked module sources into
# /home/ubuntu/go/pkg/mod; go test primes the content-addressed build cache
# at /home/ubuntu/.cache/go-build.
RUN su -s /bin/bash ubuntu -c 'export PATH=/opt/go/bin:$PATH; cd /app/src && go get -v ./... > /tmp/get.log 2>&1; grep -c "downloading" /tmp/get.log; test -d /home/ubuntu/go/pkg/mod'
RUN su -s /bin/bash ubuntu -c 'export PATH=/opt/go/bin:$PATH; cd /app/src && go test -v ./... > /tmp/warm.log 2>&1; echo "warm passes: $(grep -c -- "--- PASS" /tmp/warm.log)"; echo "warm failures: $(grep -c -- "--- FAIL" /tmp/warm.log)"'

# ---- smoke: prove the shipped state reproduces both directions --------------
# Scratch copies only; /app/src stays pristine at the parent commit. See
# environment/smoke.sh.
COPY smoke.sh /tmp/smoke.sh
RUN su -s /bin/bash ubuntu -c 'bash /tmp/smoke.sh' && rm -f /tmp/smoke.sh

# ---- integrity pins for the verifier ----------------------------------------
# Root-owned and read-only; the verifier sha256-checks these before trusting
# anything the run produces. Recorded in the same RUN that writes them.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/yaml_docs_test.go > /opt/pins/golden.sha256 \
 && sha256sum /opt/go/bin/go /usr/bin/git > /opt/pins/toolchain.sha256 \
 && chmod -R 555 /opt/golden /opt/pins \
 && chmod 444 /opt/golden/yaml_docs_test.go /opt/pins/*.sha256 \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "pins recorded"

WORKDIR /app
ENV HOME=/home/ubuntu \
    PATH=/opt/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

COPY --chown=1000:1000 files/ /app/
RUN chmod a+rwX /app

USER ubuntu

CMD ["/bin/bash"]