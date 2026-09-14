# boom-ground: an upstream-clone debugging task on tmux/tmux.
#
# The agent gets a real tmux source tree at a buildable master commit that
# predates the regression test (so there is no reproduction in the tree), with
# the real upstream bug present: respawning a pane while a control-mode client
# is behind on it leaves stale control-offsets that point into the replaced
# screen buffer, and the server crashes in input_parse a moment later.
#
# Base:       19a085a6727650ae660196a38e1a412f1b386615 (master, just before
#              the test commit for upstream issue #5498 was added; buildable,
#              contains the bug, contains no respawn-pane-control-lag test).
# Fix:        4714f478fed87ae2c510ecd035aa89c5a90dedf8 ("reset the control mode
#              offsets" on pane respawn, control.c + spawn.c + tmux.h).
# Fix merge:  22b36797526758ff3ed3407c1bbc3cde26277aaf (master merge that also
#              carries the regression test regress/respawn-pane-control-lag.sh).
#
# The image clones SHALLOW only the base commit into /app/src (no master-tip
# objects, so no fixed code is readable offline: build asserts both the fix
# commit and the merge commit are absent). The pristine parent build is copied
# to /opt/prefix/tmux and the pristine parent source to /opt/prefix/src so the
# verifier can run the agent's reproduction and the project's regress slice
# against the un-fixed code. The regression test is extracted from the fix-side
# tree via a throwaway /tmp bare clone that is deleted afterwards.
#
# Measured on this host inside bench-base:ubuntu-24.04 at 1 CPU-equivalent:
# commit base ~1.5 s, apt deps ~45 s, autogen+configure+make -j8 ~16 s, full
# make -j1 after touching tmux.h ~28 s. The regress scripts and golden test run
# headless (detached sessions, control mode over pipes, sockets under /tmp).
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG BASE_SHA=19a085a6727650ae660196a38e1a412f1b386615
ARG FIX_SHA=4714f478fed87ae2c510ecd035aa89c5a90dedf8
ARG GOLDEN_SHA=22b36797526758ff3ed3407c1bbc3cde26277aaf
# sha256 of the regression test file as extracted (pinned; the verifier
# re-checks it too):
# regress/respawn-pane-control-lag.sh @ GOLDEN_SHA =
#   a0aeeb2719cc163664d2e535ed74731a90c596c10534b12b3cdad1d5d064372d

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      build-essential autoconf automake libtool pkg-config bison byacc \
      libevent-dev libncurses-dev libutempter-dev \
 && rm -rf /var/lib/apt/lists/*

# ---- working clone: shallow, ONLY the buggy base commit --------------------
# git init + fetch --depth 1 of the base SHA; no master-tip object ever enters
# this repo, so the fixed source is not readable offline by any git command.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/tmux/tmux.git \
 && git fetch -q --depth 1 origin $BASE_SHA \
 && git checkout --detach -q FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$BASE_SHA" \
 && ! git cat-file -e "$FIX_SHA^{commit}" \
 && ! git cat-file -e "$GOLDEN_SHA^{commit}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- build + pristine snapshots in ONE layer (no duplicated bytes) ---------
RUN cd /app/src \
 && ./autogen.sh \
 && ./configure \
 && make -j8 \
 && mkdir -p /opt/prefix/src \
 && git archive --format=tar HEAD | tar -x -C /opt/prefix/src \
 && cp /app/src/tmux /opt/prefix/tmux \
 && test -x /opt/prefix/tmux \
 && test -f /opt/prefix/src/regress/pane-ops.sh \
 && find /opt/prefix -type f -exec chmod a+r {} \; \
 && chmod a+rx /opt/prefix/tmux /opt/prefix/src /opt/prefix/src/regress \
 && chown -R 1000:1000 /app/src

# ---- extract the regression test via a throwaway bare clone ----------------
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/tmux/tmux.git \
 && git fetch -q --depth 1 origin $GOLDEN_SHA \
 && mkdir -p /opt/golden \
 && git show "$GOLDEN_SHA:regress/respawn-pane-control-lag.sh" \
      > /opt/golden/respawn-pane-control-lag.sh \
 && test "$(sha256sum /opt/golden/respawn-pane-control-lag.sh | cut -d' ' -f1)" \
      = "a0aeeb2719cc163664d2e535ed74731a90c596c10534b12b3cdad1d5d064372d" \
 && chmod a+r /opt/golden/respawn-pane-control-lag.sh \
 && cd / && rm -rf /tmp/fixsrc \
 && ! git -C /app/src cat-file -e "$FIX_SHA^{commit}" \
 && ! git -C /app/src cat-file -e "$GOLDEN_SHA^{commit}"

WORKDIR /app
CMD ["/bin/bash"]