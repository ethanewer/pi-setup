FROM bench-base:ubuntu-24.04

# cistern-bell: a real upstream bug (tmux target resolution) inside a real
# upstream checkout. Everything the agent will build with is installed here;
# the trial has no network, and the build must happen inside the trial budget.

# Build toolchain for tmux's autotools build, all from Ubuntu apt (the
# project's own documented build prerequisites). runtime deps deliberately
# unpinned (tmux pins no runtime dependencies; apt is not version-pinned in
# this suite by design).
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool pkg-config \
        bison byacc libevent-dev libncurses-dev libutempter-dev git \
 && rm -rf /var/lib/apt/lists/*

# The trial may run as uid 1000 against this root-owned clone, and the
# build-time git operations here need an identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---------------------------------------------------------------------------
# Pinned upstream checkout. 73db0a54 is the buildable master-line tree whose
# cmd-find.c contains the bug (strtonum(window + 1, 1, INT_MAX, NULL) with the
# error discarded at both the window and the pane offset sites). The purely
# openbsd-line sibling commit 557967c3 carries the same code but a BSD-only
# Makefile with no autogen.sh/configure.ac, so it cannot build on Ubuntu; this
# is the tree the reproduction was measured against.
# Shallow: the agent needs the tree, not its archaeology; a single-commit
# history also means the future fix commit is not reachable from this clone.
ARG UPSTREAM_SHA=73db0a54e5ae5abf80bb790829222c9760f60b1d
RUN mkdir -p /app/tmux && cd /app/tmux \
 && git init -q \
 && git remote add origin https://github.com/tmux/tmux.git \
 && git fetch -q --depth 1 origin $UPSTREAM_SHA \
 && git checkout -q FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && test -f cmd-find.c && test -f configure.ac && test -f autogen.sh

# Pre-build the buggy tree so the image carries a working "before" binary and
# the agent's rebuild after the fix is incremental. autogen+configure+make are
# tmux's own documented build steps; bison/lex regenerate cmd-parse.c from
# cmd-parse.y (the tree keeps only the .y source).
RUN cd /app/tmux \
 && ./autogen.sh \
 && ./configure \
 && make -j4 \
 && test -x /app/tmux/tmux \
 && echo "parent build ok"

# ---------------------------------------------------------------------------
# The project's own regression tests for this behaviour (regress/targets.sh
# and regress/targets-panes.sh as committed upstream), fetched at build time
# from the merge commit d44bfda2 that contains BOTH the tests and the fix.
# They are never committed into this task tree; they are extracted into the
# image so the verifier can run upstream's untouched checks against the
# agent's binary. A throwaway repo keeps the fix objects out of /app/tmux's
# object store, so the fix commit is not reachable from the agent's clone.
RUN mkdir -p /opt/golden \
 && git init -q /tmp/golden-src \
 && cd /tmp/golden-src \
 && git remote add origin https://github.com/tmux/tmux.git \
 && git fetch -q --depth 1 origin d44bfda26d2468b5f474087b56f93eda34c541b6 \
 && git show d44bfda26d2468b5f474087b56f93eda34c541b6:regress/targets.sh > /opt/golden/targets.sh \
 && git show d44bfda26d2468b5f474087b56f93eda34c541b6:regress/targets-panes.sh > /opt/golden/targets-panes.sh \
 && test -s /opt/golden/targets.sh && test -s /opt/golden/targets-panes.sh \
 && grep -q "can't find window: +0" /opt/golden/targets.sh \
 && grep -q "can't find pane: +0" /opt/golden/targets-panes.sh \
 && echo 'ec3acd53877b645abf848a849fd6dd6b97a7d79142fc599e96e4c56d9a0a1f34  /opt/golden/targets.sh' | sha256sum -c - \
 && echo 'be45c059315ae2c52a515944a177ee1ab933d31d76b95573ba902ae08394eaa6  /opt/golden/targets-panes.sh' | sha256sum -c - \
 && cd / && rm -rf /tmp/golden-src

# The trial may run as root or uid 1000; either must be able to edit and
# rebuild in the clone.
RUN chmod -R a+rwX /app && echo "cistern-bell image ok"

WORKDIR /app