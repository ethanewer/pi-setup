# sennit-foresheet: tmux/tmux issue #5576 — malformed relative window/pane
# targets (e.g. +0, +foo, -0) are silently accepted instead of rejected.
#
# The image clones tmux/tmux at the PARENT commit
# 73db0a54e5ae5abf80bb790829222c9760f60b1d (the project's own test-first
# commit "Tests from GitHub issue 5576." on the master line: the regression
# checks are already present and FAILING, and cmd-find.c still contains the
# bug), so the agent gets the real repository with the real bug in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>` and left detached there, so the ONLY commit object in
# /app/src/.git is the parent itself. The fix commits are unreachable:
#   d44bfda26d2468b5f474087b56f93eda34c541b6 (the master merge that brought
#   the fix to the buildable line) and
#   00f3899aea035666fa9e7bd60bc7c2cf36c8e745 (the OpenBSD-dev-line fix
#   commit whose tree is not Linux-buildable).
# The golden tests (the fix-tree version of regress/, byte-identical to the
# parent tree's) are extracted from a THROWAWAY clone that is deleted, so the
# fix bytes never land in the working clone or in this task tree.
#
# Deps per the slot's install recipe: build-essential autoconf automake
# libtool pkg-config bison byacc libevent-dev libncurses-dev libutempter-dev.
# The project builds with ./autogen.sh && ./configure && make; the expensive
# warm build runs once here so the offline 1-CPU trial only ever recompiles
# incrementally (a changed .c file relinks in ~1s).
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=73db0a54e5ae5abf80bb790829222c9760f60b1d
ARG FIX_SHA=d44bfda26d2468b5f474087b56f93eda34c541b6
ARG FIX_SHA_DEV=00f3899aea035666fa9e7bd60bc7c2cf36c8e745

# ---- toolchain ----------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool pkg-config bison byacc \
        libevent-dev libncurses-dev libutempter-dev \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: the pinned parent commit and nothing else -----------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/tmux/tmux.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA_DEV}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- golden tests: whole regress/ dir from the fix tree ------------------
# Throwaway clone, deleted afterwards. The upstream test bytes never enter
# this task tree (they only ever live at /opt/golden inside the image) and
# the fix commits never exist inside /app/src/.git.
RUN git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/tmux/tmux.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && git -C /tmp/fixsrc checkout -q --detach FETCH_HEAD \
 && mkdir -p /opt/golden \
 && cp -a /tmp/fixsrc/regress /opt/golden/regress \
 && grep -q 'check_fail "can.t find window: +0"' /opt/golden/regress/targets.sh \
 && grep -q 'check_fail "can.t find pane: +0" "p:0.+0"' /opt/golden/regress/targets-panes.sh \
 && cd / \
 && rm -rf /tmp/fixsrc

# ---- warm build: compile once so the offline trial recompiles only the
# changed object and relinks -------------------------------------------------
RUN cd /app/src \
 && ./autogen.sh \
 && ./configure \
 && make -j8 \
 && chmod -R a+rwX /app/src /opt/golden

WORKDIR /app
COPY files/ /app/

# Non-recursive on purpose. `files/` is empty, so the COPY above adds nothing and
# /app contains only src/, which the warm-build RUN already made a+rwX in the same
# layer that compiled it. A `chmod -R` here would rewrite the whole compiled tree
# into a fresh copy-on-write layer -- the same bytes stored twice -- to change
# nothing. Only the /app directory itself still needs the bit.
RUN chmod a+rwX /app

CMD ["/bin/bash"]