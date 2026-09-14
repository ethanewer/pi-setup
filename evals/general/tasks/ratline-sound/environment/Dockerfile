# ratline-sound: spf13/cobra child help omits a flag that shadows a parent
# persistent flag, and shows the parent's flag under Global Flags instead
# (upstream issue #1776, fixed by commit 22b617914c8890ba20db7ceafcdc2ef4ca4817d3).
#
# The image clones spf13/cobra SHALLOW and detaches onto the PARENT commit
# (dbf85f6104904d539cabceebec234e817fa0df0c), so the trial agent gets the real
# tree with the real bug still in it, with the fix commit NOT reachable. The
# project's own regression test for the bug (command_test.go at the FIX commit)
# is extracted at build time into /opt/golden/ through a SEPARATE throwaway
# bare clone under /tmp which is rm -rf'd afterwards, so the fix object never
# enters the shipped repository (/app/src/.git). The golden file is NOT
# overlaid onto the working tree: per the v4.3 authoring contract the agent
# must author its own failing reproduction (/app/repro/repro_test.go) before
# fixing anything; the verifier copies the golden test in at verify time.
#
# Dependency pins from the verified issue entry: the V ("go") language toolchain
# 1.24.0 (go.dev/dl tarball, linux amd64) and the module pins in the
# repository's tracked go.sum (pflag v1.0.5, yaml.v3 v3.0.1, mousetrap v1.0.1,
# go-md2man/v2 v2.0.2). Module and compile caches are warmed at build time
# under world-writable paths (GOMODCACHE/GOCACHE) so the trial runs entirely
# from cache with no network.
#
# The go test suite must run as an UNPRIVILEGED user: one upstream test
# (TestFailGenFishCompletionFile) opens a 0400 file and expects "permission
# denied", which root bypasses. bench-base already ships the `ubuntu` user
# (uid 1000); the verifier and oracle drop privileges to it with setpriv
# (util-linux). The warm-up build runs as that same user, and the whole tree
# plus the go caches are chmod'ed world-writable in the SAME RUN that builds
# them, so the image stores those bytes once.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=dbf85f6104904d539cabceebec234e817fa0df0c
ARG FIX_SHA=22b617914c8890ba20db7ceafcdc2ef4ca4817d3

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- go 1.24.0 toolchain (pinned), plus patch/setpriv for oracle/verifier ---
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
 && git fetch --depth 1 origin "$UPSTREAM_SHA" \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone only, deleted afterwards, so the fix commit object never
# exists anywhere reachable from /app/src/.git. The golden file is harness-owned
# (root, read-only) and the verifier verifies its sha256.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/spf13/cobra.git \
 && git fetch --depth 1 origin "$FIX_SHA" \
 && mkdir -p /opt/golden \
 && git show "$FIX_SHA":command_test.go > /opt/golden/command_test.go \
 && test -s /opt/golden/command_test.go \
 && grep -q "func TestHelpCommandExecutedOnChildWithFlagThatShadowsParentFlag" /opt/golden/command_test.go \
 && grep -q "func TestChildFlagShadowsParentPersistentFlag" /opt/golden/command_test.go \
 && chmod 0444 /opt/golden/command_test.go \
 && chmod 0555 /opt/golden \
 && cd / && rm -rf /tmp/fixsrc \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}"

# ---- go caches + tree: warm at build, one layer, world-writable, offline ----
ENV GOMODCACHE=/opt/go/pkg/mod \
    GOCACHE=/opt/go/gocache \
    PATH=/opt/go/bin:$PATH
RUN mkdir -p "$GOMODCACHE" "$GOCACHE" \
 && chown -R 1000:1000 /opt/go/pkg/mod /opt/go/gocache /app /home/ubuntu \
 && setpriv --reuid=1000 --regid=1000 --clear-groups \
      env HOME=/home/ubuntu PATH=/opt/go/bin:$PATH \
          GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache \
      sh -c 'set -e; cd /app/src && go get -v ./... > /tmp/warm-get.log 2>&1 && go test -v ./... > /tmp/warm-full.log 2>&1' \
 && test "$(grep -c 'PASS:' /tmp/warm-full.log)" -gt 200 \
 && ! grep -q 'FAIL' /tmp/warm-full.log \
 && test "$(cat /app/src/go.mod | head -1)" = "module github.com/spf13/cobra" \
 && git -C /app/src status --porcelain | wc -l | grep -q '^0$' \
 && chmod -R a+rwX /app /opt/go/pkg/mod /opt/go/gocache /home/ubuntu \
 && rm -f /tmp/warm-get.log /tmp/warm-full.log

WORKDIR /app

# ---- build-time self-check: both directions inside THIS image --------------
# 1) overlay the golden regression test onto the parent tree: the two tests
#    must FAIL (the bug is present), with the mined symptom in the log;
# 2) apply the shipped one-line fix: the same two tests must PASS, and the
#    full suite must stay green;
# 3) revert everything; the tree must end pristine (no diff vs the parent),
#    reproducing the exact state the trial agent starts from.
# The check runs with set -e, so the build fails closed if the bug ever stops
# reproducing inside this image.
RUN cp /opt/golden/command_test.go /app/src/command_test.go \
 && test "$(git -C /app/src status --porcelain)" = " M command_test.go" \
 && setpriv --reuid=1000 --regid=1000 --clear-groups \
      env HOME=/home/ubuntu PATH=/opt/go/bin:$PATH \
          GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache \
      sh -c 'cd /app/src && ! go test -v ./... -run TestHelpCommandExecutedOnChildWithFlagThatShadowsParentFlag > /tmp/self1.log 2>&1' \
      && grep -q 'Help text mismatch' /tmp/self1.log \
      && grep -q -- '--foo   parent foo usage' /tmp/self1.log \
 && git -C /app/src checkout -- command_test.go \
 && python3 -c "p='/app/src/command.go'; s=open(p).read(); old='if c.lflags.Lookup(f.Name) == nil && c.parentsPflags.Lookup(f.Name) == nil {'; new='if c.lflags.Lookup(f.Name) == nil && f != c.parentsPflags.Lookup(f.Name) {'; assert old in s, 'buggy guard not found in command.go'; open(p,'w').write(s.replace(old,new))" \
 && cp /opt/golden/command_test.go /app/src/command_test.go \
 && setpriv --reuid=1000 --regid=1000 --clear-groups \
      env HOME=/home/ubuntu PATH=/opt/go/bin:$PATH \
          GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache \
      sh -c 'cd /app/src && go test -v ./... -run "TestHelpCommandExecutedOnChildWithFlagThatShadowsParentFlag|TestChildFlagShadowsParentPersistentFlag" > /tmp/self2.log 2>&1 && go test -v ./... > /tmp/self3.log 2>&1' \
 && ! grep -q 'FAIL' /tmp/self2.log \
 && ! grep -q 'FAIL' /tmp/self3.log \
 && git -C /app/src checkout -- command.go command_test.go \
 && test -z "$(git -C /app/src status --porcelain)" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && rm -f /tmp/self1.log /tmp/self2.log /tmp/self3.log