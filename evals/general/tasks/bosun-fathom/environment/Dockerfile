ARG UPSTREAM_SHA_PARENT=6244e635a1a5aa4d401826b1e970d59a3f6cbf7c
ARG UPSTREAM_SHA_FIX=4ab1862dc04783b6615807d4b4511388c6b30364

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

ENV CARGO_HOME=/opt/cargo

# Build chain: standard Debian tooling plus the Rust 1.98.1 toolchain from
# the official dist tarball (static.rust-lang.org no longer carries
# rustup-init and sh.rust-lang.org does not resolve on this network). The
# repository's Cargo.lock pins every crate, but the toolchain line is not
# pinned by Cargo.lock, so it is pinned explicitly here, exactly as the
# mining run did. Cargo's registry cache lives in /opt/cargo (read by cargo
# of any user); only cargo's bookkeeping files there are ever written.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential pkg-config git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

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

# Warm debug build at the parent commit (~20 s on one core; crates are
# downloaded from crates.io in this layer only). The trial has no network,
# so this layer IS the warm tree: the agent edits one source file and only
# needs an incremental `cargo build --locked` to relink. Ownership is fixed
# in this SAME layer (never a later chown of the tree, which would double
# the layer): the tree and the cargo cache end up owned and writable by
# root and uid 1000 alike.
RUN cd /app/src \
 && cargo build --locked > /tmp/warm-build.log 2>&1; rc=$?; \
    tail -4 /tmp/warm-build.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit 1; fi; \
    test -x /app/src/target/debug/rg \
 && test -z "$(git status --porcelain)" \
 && echo "warm build ok, working tree clean" \
 && mkdir -p /opt/prefix \
 && cp /app/src/target/debug/rg /opt/prefix/rg \
 && chmod 755 /opt/prefix/rg \
 && chown -R 1000:1000 /app/src /opt/cargo \
 && chmod -R a+rwX /app/src /opt/cargo \
 && echo "tree and cargo cache handed to uid 1000"

# Parent-direction confirmation 1/2 in THIS image: the exact user-visible
# symptom must reproduce against the freshly built binary, so the task's
# oracle can actually pass. A file with five 5-byte lines searched with
# --stats -m2 foo reports '0 bytes searched' at the parent (the correct
# value for two consumed 5-byte lines is 10); everything else in the stats
# block is correct.
RUN cat > /tmp/reprocheck.sh <<'SH'
#!/bin/bash
set -u
tmp=$(mktemp -d /tmp/reprocheck.XXXXXX) || exit 1
printf 'foo1\nfoo2\nfoo3\nfoo4\nfoo5\n' > "$tmp/haystack" || exit 1
( cd "$tmp" && /app/src/target/debug/rg --stats -m2 foo . > out.txt 2> err.txt )
rc=$?
echo "direct repro rc=$rc"
grep -E "[0-9]+ matches|[0-9]+ bytes searched" "$tmp/out.txt" || true
if [ "$rc" -ne 0 ]; then
    echo "REPRO: rg exited nonzero - failing closed"; rm -rf "$tmp"; exit 1
fi
if ! grep -q "2 matches" "$tmp/out.txt"; then
    echo "REPRO: '2 matches' not in output - failing closed"
    rm -rf "$tmp"; exit 1
fi
if ! grep -q "0 bytes searched" "$tmp/out.txt"; then
    echo "REPRO: '0 bytes searched' (the bug) not seen - failing closed"
    rm -rf "$tmp"; exit 1
fi
rm -rf "$tmp"
echo "parent-direction: bug reproduces in this exact image"
SH
RUN chmod 755 /tmp/reprocheck.sh \
 && bash /tmp/reprocheck.sh \
 && rm -f /tmp/reprocheck.sh

# Parent-direction confirmation 2/2 in THIS image: the warm cargo cache and
# the writable tree work for uid 1000 (the user the trial may run as), and
# an offline incremental rebuild succeeds with nothing to do. This is also
# where every TEST-profile dependency is warmed: `cargo build` only fetches
# build deps, so the test-only crates (regex, grep-regex, aho-corasick, ...)
# would otherwise be downloaded at the first `cargo test`, which must never
# happen in an offline trial. The `--no-run` passes compile the integration
# test binary and the searcher unit-test binary exactly as the trial will
# use them; the second (--offline) passes prove the cache is complete and
# the trial needs no network at all.
RUN su -s /bin/bash ubuntu -c 'set -u; cd /app/src && export PATH="/usr/local/bin:$PATH" && \
    cargo test --test integration --no-run --locked > /tmp/warm-test.log 2>&1 && \
    cargo test -p grep-searcher --no-run --locked >> /tmp/warm-test.log 2>&1 && \
    cargo test --test integration --no-run --locked --offline >> /tmp/warm-test.log 2>&1 && \
    cargo test -p grep-searcher --no-run --locked --offline >> /tmp/warm-test.log 2>&1 && \
    tail -2 /tmp/warm-test.log' \
 && echo "uid-1000 offline rebuild + warm test cache ok"

# Extract the project's own regression test for this bug (r2944, which the
# fix commit appends to tests/regression.rs) into /opt/golden using a
# THROWAWAY clone that is deleted immediately afterwards, so the fix commit
# never lands in /app/src and no upstream test bytes enter this task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/BurntSushi/ripgrep.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/regression.rs > /opt/golden/regression.rs \
 && test -s /opt/golden/regression.rs \
 && grep -q "r2944_incorrect_bytes_searched" /opt/golden/regression.rs \
 && grep -q "10 bytes searched" /opt/golden/regression.rs \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && echo "golden regression module extracted"

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
# build/test toolchain itself, so the verifier can detect substitution. The
# trial and the verifier both run the compiled binary and the project's own
# test machinery; an adversarial root agent could otherwise swap the
# compiler or the golden test for a stub that fakes a green run. /opt is
# read-only for everyone afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/regression.rs > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/rg > /opt/pins/prefix-rg.sha256 \
 && sha256sum /usr/local/bin/rustc /usr/local/bin/cargo /usr/bin/gcc \
                 /usr/bin/git /usr/bin/bash /usr/bin/ld /usr/bin/cc \
      > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/regression.rs \
 && test "$(wc -l < /opt/pins/toolchain.sha256)" = 7 \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-rg.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + prefix binary + toolchain pinned"

COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/README-BUILD.md

WORKDIR /app

CMD ["/bin/bash"]