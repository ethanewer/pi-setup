ARG UPSTREAM_SHA_PARENT=e6cac8b119d0d50646b3ba1aaf53e648c779901a
ARG UPSTREAM_SHA_FIX=12dd455ee9aa731acfeb0d2dfed568a0103cae73

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Shared cargo home so the warm build products (downloaded crates registry
# cache and index) are visible to the trial and the verifier regardless of
# which uid the container runs as. Created world-writable up front so build,
# trial and verifier (root or uid 1000) can all write lock files here.
ENV CARGO_HOME=/opt/cargo
RUN install -d -m 777 /opt/cargo

# Build dependencies: the pure-stdlib ripgrep build needs a C toolchain and
# linker for the ring crate and friends, plus curl to download the Rust
# toolchain. Git config so the tree works for the trial user (uid 1000).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential pkg-config git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Rust 1.98.1 toolchain, from the official dist tarball (static.rust-lang.org
# no longer carries rustup-init; sh.rust-lang.org does not resolve on this
# network). Only the compiler + std library + cargo are installed; docs and
# rustfmt/clippy are dropped to keep the image small.
RUN curl -sO https://static.rust-lang.org/dist/2026-09-03/rust-1.98.1-x86_64-unknown-linux-gnu.tar.xz \
 && tar xf rust-1.98.1-x86_64-unknown-linux-gnu.tar.xz \
 && ./rust-1.98.1-x86_64-unknown-linux-gnu/install.sh \
 && rm -rf rust-1.98.1-x86_64-unknown-linux-gnu.tar.xz rust-1.98.1-x86_64-unknown-linux-gnu \
 && rustc --version \
 && cargo --version

# Clone the REAL upstream repository (BurntSushi/ripgrep) at exactly the
# parent commit, with the shallowest possible history: `git init` + one
# depth-1 fetch of the pinned SHA means the object store in /app/src holds
# ONLY the parent commit. The fix commit (which an agent must not be able to
# look up or fetch) is NEVER fetched into this clone; it is asserted
# unreachable below.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/BurntSushi/ripgrep.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# Warm release build at the parent commit (~10 minutes on one core; crates
# are downloaded from crates.io in this layer only). The trial has no
# network, so this layer IS the warm tree: the agent edits one source file
# and only needs an incremental `cargo build --release --locked` to relink.
# Ownership is fixed in this SAME layer (never a later chown of the tree,
# which would double the layer): the tree and the cargo cache end up owned
# and writable by root and uid 1000 alike.
RUN cd /app/src \
 && cargo build --release --locked > /tmp/warm-build.log 2>&1; rc=$?; \
    tail -4 /tmp/warm-build.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit 1; fi; \
    test -x /app/src/target/release/rg \
 && test -z "$(git status --porcelain)" \
 && echo "warm build ok, working tree clean" \
 && mkdir -p /opt/prefix \
 && cp /app/src/target/release/rg /opt/prefix/rg \
 && chmod 755 /opt/prefix/rg \
 && chown -R 1000:1000 /app/src /opt/cargo \
 && chmod -R a+rwX /app/src /opt/cargo \
 && echo "tree and cargo cache handed to uid 1000"

# Parent-direction confirmation in THIS image: the exact user-visible symptom
# must reproduce against the freshly built binary, so the task's oracle can
# actually pass. A file containing a single newline, searched with a pattern
# that matches empty (here 'x?') using --crlf --color always, panics:
# release mode reports an out-of-bounds index into a 1-byte buffer while
# trimming the CR of an empty CRLF line, and exits 101 with no stdout.
RUN cat > /tmp/reprocheck.sh <<'SH'
#!/bin/bash
set -u
tmp=$(mktemp -d /tmp/reprocheck.XXXXXX) || exit 1
printf '\n' > "$tmp/test.txt" || exit 1
(cd "$tmp" && /app/src/target/release/rg 'x?' --crlf --color always test.txt \
        > out.txt 2> err.txt)
rc=$?
echo "direct repro rc=$rc"
echo "--- stdout:"; head -3 "$tmp/out.txt"
echo "--- stderr:"; head -6 "$tmp/err.txt"
if [ "$rc" -eq 0 ]; then
    echo "REPRO DID NOT CRASH - failing closed"; rm -rf "$tmp"; exit 1
fi
if ! grep -qi "panicked" "$tmp/err.txt" && \
   ! grep -qi "index out of bounds" "$tmp/err.txt"; then
    echo "panic signature not found in stderr - failing closed"
    rm -rf "$tmp"; exit 1
fi
rm -rf "$tmp"
echo "parent-direction: bug reproduces in this exact image"
SH
RUN chmod 755 /tmp/reprocheck.sh \
 && bash /tmp/reprocheck.sh \
 && rm -f /tmp/reprocheck.sh

# Extract the project's own regression test for this bug (test r1765, which
# the fix commit appends to tests/regression.rs) into /opt/golden using a
# THROWAWAY clone that is deleted immediately afterwards, so the fix commit
# never lands in /app/src and no upstream test bytes enter this task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/BurntSushi/ripgrep.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/regression.rs > /opt/golden/regression.rs \
 && test -s /opt/golden/regression.rs \
 && grep -q "r1765" /opt/golden/regression.rs \
 && grep -q "issues/1765" /opt/golden/regression.rs \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone. The
# object store holds exactly one commit (the parent), so both the commit
# object and every blob changed by the fix are absent.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# Record sha256 pins of the golden test, of the pre-fix binary, and of the
# build/toolchain itself, so the verifier can detect substitution. An
# adversarial root agent could otherwise swap the compiler or the golden
# test for a stub that fakes a green run. /opt is read-only for everyone
# afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/regression.rs > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/rg > /opt/pins/prefix-rg.sha256 \
 && sha256sum /usr/local/bin/rustc /usr/local/bin/cargo /usr/bin/gcc \
                 /usr/bin/git /usr/bin/bash /usr/bin/ld \
      > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix \
 && chmod 444 /opt/pins/*.sha256 \
 && chmod 444 /opt/golden/regression.rs \
 && test "$(wc -l < /opt/pins/toolchain.sha256)" = 6 \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-rg.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + prefix binary + toolchain pinned"

COPY files/ /app/
RUN chmod 644 /app/README-BUILD.md

WORKDIR /app

CMD ["/bin/bash"]