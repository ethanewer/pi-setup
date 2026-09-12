# cistern-anchor: spf13/cobra command resolution drops a flag value that
# happens to equal a subcommand name (upstream issue #1781).
#
# The image clones spf13/cobra SHALLOW at the PARENT commit (the real upstream
# bug is present in the working tree), extracts the project's own regression
# test (command_test.go) from the FIX commit at build time into /opt/golden/,
# and overlays it onto the working tree exactly as the mining reproduction did,
# so `go test -v ./... -run TestFind` fails inside the image with the mined
# symptom. The fix commit is fetched only into a throwaway bare clone that is
# deleted, so it is never reachable from /app/src/.git.
#
# Dependency pins from the verified issue: the "go" language toolchain 1.24.0
# (go.dev/dl tarball, linux amd64) and the module pins in the repository's
# tracked go.sum (pflag v1.0.5, yaml.v3 v3.0.1, mousetrap v1.0.1,
# go-md2man/v2 v2.0.2). Module and compile caches are warmed at build time
# under world-writable paths (GOMODCACHE/GOCACHE) so the offline trial runs
# entirely from cache.
#
# The go test suite must run as an UNPRIVILEGED user: one upstream test
# (TestFailGenFishCompletionFile) opens a 0400 file and expects "permission
# denied", which root bypasses. bench-base already ships the `ubuntu` user
# (uid 1000); the verifier drops privileges to it with setpriv (util-linux).
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=cc7e235fc26cfd0b5ae36c960f399eea4badaa3e
ARG FIX_SHA=6b0bd3076cfafd1c108264ed1e4aa0c0fe3f8537

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- go 1.24.0 toolchain (pinned), plus patch/setpriv for the oracle/verifier
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git patch util-linux \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/go.tgz https://go.dev/dl/go1.24.0.linux-amd64.tar.gz \
 && tar -C /opt -xzf /tmp/go.tgz \
 && rm -f /tmp/go.tgz \
 && test -x /opt/go/bin/go

# ---- working clone: buggy parent commit, fix commit unreachable -------------
RUN git clone --depth 1 https://github.com/spf13/cobra.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin cc7e235fc26cfd0b5ae36c960f399eea4badaa3e \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/spf13/cobra.git \
 && git fetch --depth 1 origin 6b0bd3076cfafd1c108264ed1e4aa0c0fe3f8537 \
 && mkdir -p /opt/golden \
 && git show 6b0bd3076cfafd1c108264ed1e4aa0c0fe3f8537:command_test.go \
      > /opt/golden/command_test.go \
 && test -s /opt/golden/command_test.go \
 && grep -q "func TestFind" /opt/golden/command_test.go \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the regression test into the working tree -----------------------
# So `go test -v ./... -run TestFind` fails in the image exactly as mined.
RUN cp /opt/golden/command_test.go /app/src/command_test.go \
 && cd /app/src \
 && test "$(git diff --name-only)" = "command_test.go" \
 && cmp -s /opt/golden/command_test.go command_test.go \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- go caches: warm at build, writable by any trial uid, no network needed --
ENV GOMODCACHE=/opt/go/pkg/mod \
    GOCACHE=/opt/go/gocache \
    PATH=/opt/go/bin:$PATH
RUN mkdir -p "$GOMODCACHE" "$GOCACHE"

# ---- warm the module build and fail closed if the bug is not present ---------
# (warm-up runs as ubuntu so HOME state lands under /home/ubuntu; this is the
#  same user the verifier uses - the trial is offline, so it must never need
#  to re-fetch, and it must be able to write new cache entries itself)
RUN chown -R 1000:1000 /opt/go/pkg/mod /opt/go/gocache /app /home/ubuntu \
 && setpriv --reuid=1000 --regid=1000 --clear-groups \
      env HOME=/home/ubuntu PATH=/opt/go/bin:$PATH \
          GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache \
      sh -c 'cd /app/src && go get -v ./... > /tmp/warm-get.log 2>&1 \
             && go test -v ./... -run TestFind > /tmp/warm-test.log 2>&1; \
             rc=$?; test "$rc" -ne 0' \
 && grep -q 'Expected: \[--foo child --bar something\]' /tmp/warm-test.log \
 && grep -q 'Got: \[--foo --bar something child\]' /tmp/warm-test.log \
 && test "$(cat /app/src/go.mod | head -1)" = "module github.com/spf13/cobra" \
 && rm -f /tmp/warm-get.log /tmp/warm-test.log \
 && chmod -R a+rwX /app /opt/go/pkg/mod /opt/go/gocache /home/ubuntu

WORKDIR /app
CMD ["/bin/bash"]