# pintle-berm: rust-lang/regex leftmost-match bug when a pattern's first
# alternative is optional (upstream issue #1060).
#
# The image clones rust-lang/regex SHALLOW at the PARENT commit (release
# 1.9.2, bbf0b38df618734b92d7b92acc8a8bf31b6d0046) into /app/src where the
# bug is live, pre-builds the workspace as cached image layers so the
# agent's edit-compile-test cycle is incremental, and extracts the project's
# own regression test for the bug from the FIX commit
# (73f7889021542ea80937b3adacefa5825eaa97fe) into /opt/golden-regression.toml
# through a THROWAWAY bare clone that is deleted immediately afterwards, so
# the fix object never exists in /app/src/.git (or /opt/pristine/.git) and
# cannot be read with `git log --all` or cat-file. A second pristine clone
# at /opt/pristine holds the same parent commit read-only and pre-built; the
# verifier replays the agent's own regression test against it to prove the
# agent's reproduction is genuine.
#
# rust-lang/regex is not a Terminal-Bench 2.1 source repository (checked
# against specs/tb21_source_repositories.json), it uses no submodules and no
# VCS dependencies.

ARG UPSTREAM_SHA=bbf0b38df618734b92d7b92acc8a8bf31b6d0046
ARG FIX_SHA=73f7889021542ea80937b3adacefa5825eaa97fe
ARG RUST_VERSION=1.98.1

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA
ARG FIX_SHA
ARG RUST_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Build toolchain. gcc etc. are not actually needed to build this pure-Rust
# workspace, but the mining container had them; keep the recipe identical.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates git pkg-config libssl-dev \
 && rm -rf /var/lib/apt/lists/*

# Rust toolchain, pinned to the exact line the mining run used (1.98.1).
RUN curl -sSf https://sh.rustup.rs -o /tmp/rustup.sh \
 && sh /tmp/rustup.sh -y --default-toolchain none \
 && rustup toolchain install ${RUST_VERSION} \
 && rustup default ${RUST_VERSION} \
 && rustc --version && cargo --version \
 && rustfmt --version 2>/dev/null; true \
 && rm -f /tmp/rustup.sh

# Cargo needs to create bookkeeping files (package cache, sparse-index
# locks, downloaded crate archives) inside CARGO_HOME, and the warm builds
# run as uid 1000; make the whole cargo home world-writable now. The
# executable dirs are hardened at the end of the build.
RUN chmod -R a+rwX /opt/cargo

# ---- working clone: buggy parent commit, fix commit unreachable -------------
# The clone is created with `git init` + one depth-1 fetch of the pinned
# SHA, so the object store holds ONLY the parent commit. The tree is chowned
# to uid 1000 in the same RUN that creates it so no later layer duplicates
# its bytes.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/rust-lang/regex.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && if git cat-file -e ${FIX_SHA}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && chown -R 1000:1000 /app/src

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, deleted right after; the fix commit never enters
# /app/src/.git or /opt/pristine/.git.
RUN git init -q /tmp/fix-clone \
 && cd /tmp/fix-clone \
 && git remote add origin https://github.com/rust-lang/regex.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && git show ${FIX_SHA}:testdata/regression.toml > /opt/golden-regression.toml \
 && grep -q 'name = "reverse-inner-plus-shorter-than-expected"' /opt/golden-regression.toml \
 && grep -q 'name = "reverse-inner-short"' /opt/golden-regression.toml \
 && cd / \
 && rm -rf /tmp/fix-clone \
 && test -s /opt/golden-regression.toml

# ---- warm build of the working tree (uid 1000) -------------------------------
# Compiles the whole workspace plus the integration test harness and warms
# the crates.io registry cache inside /opt/cargo. The trial has no network.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" \
  && cargo test --test integration --no-run > /tmp/warm-src.log 2>&1'; rc=$?; \
  tail -3 /tmp/warm-src.log; \
  if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
  ls /app/src/target/debug/deps/ | grep -E '^integration-[0-9a-f]+$' | head -1

# ---- smoke: the image must contain the mined failing state -------------------
# Plant the upstream regression test into the tree and require
# suite_string::default to FAIL with the mined symptom (reverse-inner
# cases), then restore the vanilla test data and require the vanilla parent
# suite to PASS. Everything in the same RUN so the tree bytes are written
# once; ends with the working tree world-writable for either trial uid.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" \
&& cp /opt/golden-regression.toml testdata/regression.toml \
&& cargo test --test integration --no-run > /tmp/smoke-build.log 2>&1 \
&& if cargo test --test integration -- suite_string::default > /tmp/smoke1.log 2>&1; then echo "ERROR: expected the reverse-inner bug to fail at the parent commit"; exit 1; fi \
&& grep -aq "reverse-inner-plus-shorter-than-expected" /tmp/smoke1.log \
&& grep -aq "reverse-inner-short" /tmp/smoke1.log \
&& git show HEAD:testdata/regression.toml > testdata/regression.toml \
&& cargo test --test integration --no-run > /tmp/smoke-restore.log 2>&1 \
&& cargo test --test integration -- suite_string::default > /tmp/smoke2.log 2>&1 \
&& chmod -R a+rwX /app/src \
&& echo "smoke ok: bug reproduced at parent, vanilla parent suite green"'; \
rc=$?; if [ $rc -ne 0 ]; then echo "SMOKE FAILED"; exit $rc; fi

# ---- pristine pre-fix clone (the verifier replays the agent repro against it) -
# Same parent commit, kept READ-ONLY and root-owned so only the root
# verifier (at grading time) writes into it; the read-only modes are applied
# at the end of the build RUN that produced the tree so no layer duplicates
# its bytes.
RUN git init -q /opt/pristine \
 && cd /opt/pristine \
 && git remote add origin https://github.com/rust-lang/regex.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && if git cat-file -e ${FIX_SHA}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /opt/pristine"; exit 1; \
    fi \
 && git config --system --add safe.directory /opt/pristine

# ---- warm build of the pristine tree (root) ----------------------------------
RUN cd /opt/pristine \
 && export PATH="/opt/cargo/bin:$PATH" \
 && cargo test --test integration --no-run > /tmp/warm-pristine.log 2>&1; rc=$?; \
    tail -3 /tmp/warm-pristine.log; \
    if [ $rc -ne 0 ]; then echo "PRISTINE WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    cd / \
    && chmod -R a-w /opt/pristine \
    && find /opt/pristine -type d -exec chmod a+rx {} \; \
    && echo "pristine built and locked read-only"

# ---- record integrity pins and harden the toolchain --------------------------
# The verifier re-checks these sha256 sums first, so a swapped cargo/rustc/git
# stub or a substituted golden test can never earn reward 1. Cargo's data
# dirs stay writable (cargo needs their locks at trial time); its bin dirs
# become root-only so a uid 1000 trial cannot swap the toolchain.
#
# The golden regression test is hidden FROM the trial user: it names the
# upstream issue URL and the exact expected spans, so a uid 1000 agent must
# not be able to read it, or the 'write your own reproduction' step reduces
# to copying it. The verifier runs as root and can still read it.
#
# Build-time logs under /tmp contain the full mined reproduction (patterns,
# haystacks, expected spans) printed by the smoke suite run; they are
# removed so the working reproduction exists nowhere in the shipped image.
#
# /app/src/.git is made root-owned and write-protected: the warm builds
# chowned it to uid 1000, and an agent that can rewrite pack objects could
# /app/src/.git is made root-owned and write-protected: the warm builds
# chowned it to uid 1000, and an agent that can rewrite pack objects could
# forge the parent blobs the scope check compares against. The working tree
# itself stays agent-writable, and read-only .git keeps status/diff usable
# while impossible to tamper (git status must run BEFORE these chmods: it
# refreshes the index and would otherwise rewrite it writable). The smoke
# build compiled the golden testdata into the integration harness; rustc's
# stale incremental artifacts retain those strings, so they are dropped too.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/cargo/bin/cargo /opt/cargo/bin/rustc /usr/bin/git \
             /opt/golden-regression.toml > /opt/pins/anchors.sha256 \
 && chmod 755 /opt/cargo /opt/cargo/bin /opt/rustup \
 && chmod -R a+rwX /opt/cargo/registry \
 && chmod 666 /opt/cargo/.global-cache /opt/cargo/.package-cache /opt/cargo/.package-cache-mutate 2>/dev/null || true \
 && chmod 555 /opt/pins \
 && chmod 444 /opt/pins/anchors.sha256 \
 && ( cd / && sha256sum -c /opt/pins/anchors.sha256 > /dev/null ) \
 && chmod 400 /opt/golden-regression.toml \
 && rm -f /tmp/smoke1.log /tmp/smoke2.log /tmp/smoke-build.log /tmp/smoke-restore.log \
       /tmp/warm-src.log /tmp/warm-pristine.log \
 && rm -rf /app/src/target/debug/incremental \
 && git -C /app/src status --porcelain | grep -q . && { echo "unexpected: /app/src dirty at build end"; exit 1; } || true \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && echo "anchors pinned; /app/src clean at parent"

COPY files/ /app/
# The working tree must be writable by either trial uid; the shipped .git
# stays root-owned and write-protected (see the pins RUN above for why), so
# it is re-hardened AFTER the tree-wide chmod in this same RUN layer.
RUN chmod -R a+rwX /app \
 && chown -R root:root /app/src/.git \
 && chmod -R a-w /app/src/.git \
 && chmod -R a+rX /app/src/.git

WORKDIR /app

# The warm builds above needed the network (they filled the registry cache);
# the trial does not have one, so fail fast offline from here on.
ENV CARGO_NET_OFFLINE=true

CMD ["/bin/bash"]