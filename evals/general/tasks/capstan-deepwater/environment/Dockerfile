# capstan-deepwater: BurntSushi/ripgrep glob-with-trailing-dot bug
# (upstream issue #2990, fix commit 4df1298127695ed1e76937f16de1a0135677ccf5).
#
# The image clones the REAL upstream repository SHALLOW at the PARENT commit
# (ba23ced8178496263af013117b70c09ce39c18e5), so the working tree ships the
# real bug: globset's file_name() drops the final path component whenever a
# path ends in a dot, and glob matching strategies keyed on the candidate
# basename/extension therefore silently stop matching for any glob whose
# final component ends in a dot (e.g. `-g '!asdf./'` on a directory named
# `asdf.` excludes nothing). The project's own regression test for the bug
# (r2990_trip_over_trailing_dot, added to tests/regression.rs by the fix) is
# extracted from the FIX commit at build time into /opt/golden; it is never
# part of this task tree and the fix commit is never reachable from /app/src.
#
# The build chain is the rustup toolchain line 1.98.1, exactly as the sibling
# ripgrep task (#3180) uses. Cargo.lock pins every crate; the toolchain line
# itself is pinned here explicitly. A build-time smoke step plants the golden
# regression test and REQUIRES it to fail inside this image, proving the
# image ships the bug at the pinned dependency versions (fail closed if it
# does not reproduce); the tree is restored byte-exact afterwards.
ARG UPSTREAM_SHA_PARENT=ba23ced8178496263af013117b70c09ce39c18e5
ARG UPSTREAM_SHA_FIX=4df1298127695ed1e76937f16de1a0135677ccf5
ARG RUST_VERSION=1.98.1
ARG GOLDEN_SHA=48708bd6aa3534e703a11b101de09a66794206ffc043be966abba3cfde07801e

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG RUST_VERSION
ARG GOLDEN_SHA

# The toolchain lives in /opt (read-only for everyone); only /app and the
# cargo target dir under /app/src are writable at trial time.
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates git pkg-config \
 && rm -rf /var/lib/apt/lists/*

RUN curl -sSf https://sh.rustup.rs -o /tmp/rustup.sh \
 && sh /tmp/rustup.sh -y --default-toolchain none \
 && rustup toolchain install ${RUST_VERSION} --profile minimal \
 && rustup default ${RUST_VERSION} \
 && rustc --version && cargo --version \
 && rm -f /tmp/rustup.sh \
 && chmod -R a+rwX /opt/cargo
# `--profile minimal` skips rust-docs/clippy/rustfmt, which nothing in the
# build, test, oracle or verifier path uses (this task only runs `cargo build`
# and `cargo test --no-run`). The trailing chmod is in this SAME RUN so the
# cargo home is made world-writable exactly once, where it was created:
# Cargo needs to create bookkeeping files (package cache, sparse-index locks,
# downloaded crate archives) inside CARGO_HOME, and the trial may run as uid
# 1000. A separate `RUN chmod -R` layer would copy every byte of /opt/cargo a
# second time (Docker layers are copy-on-write).

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/BurntSushi/ripgrep.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && chmod -R a+rwX /app/src \
 && chown -R 1000:1000 /app/src
# Ownership is fixed in this SAME RUN, while the tree is brand new: the image
# is built as root but the trial may run as uid 1000 (user `ubuntu` exists in
# the base image), so the whole tree must be writable by uid 1000 from the
# start. A later separate `RUN chown -R` would make Docker's copy-on-write
# storage rewrite every byte of /app/src into a second layer; here the chown
# is part of the layer that just created the files, so it costs nothing.

# Extract the project's own regression test for this bug (the test that the
# fix commit appends to tests/regression.rs) into /opt/golden using a
# THROWAWAY clone that is deleted immediately afterwards, so upstream test
# bytes never land in this task tree and the fix commit never lands in
# /app/src. The whole file is copied (parent's regression.rs plus this one
# appended test) and its sha256 is asserted so a moved commit fails closed.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/BurntSushi/ripgrep.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/regression.rs > /opt/golden/regression.rs \
 && test "$(sha256sum /opt/golden/regression.rs | cut -d' ' -f1)" = "${GOLDEN_SHA}" \
 && grep -q "r2990_trip_over_trailing_dot" /opt/golden/regression.rs \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# The tree is already owned by uid 1000 (see the clone RUN). WARM every cache
# the trial needs AS that user, so every writable path (target/, cargo
# bookkeeping) is owned by uid 1000 from the start and /opt stays a read-only
# toolchain. The warm pass downloads all crates.io dependencies
# (Cargo.lock-pinned) and compiles the whole workspace plus the `rg` binary
# and the test harness; the trial has no network, so this layer IS the warm
# cache.
WORKDIR /app
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo build > /tmp/warm1.log 2>&1'; rc=$?; \
    tail -5 /tmp/warm1.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    test -x /app/src/target/debug/rg && echo "rg debug binary built" || { echo "no rg binary"; exit 1; }
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --no-run > /tmp/warm2.log 2>&1'; rc=$?; \
    tail -8 /tmp/warm2.log; \
    if [ $rc -ne 0 ]; then echo "WARM TEST-BUILD FAILED (exit $rc)"; exit $rc; fi; \
    ls /app/src/target/debug/deps/ | grep -c '^integration-' | xargs -I{} echo "integration test binaries: {}"

# Smoke: prove the image ships the FAILING state. Plant the golden upstream
# regression test, rebuild the harness offline, and require the test to FAIL
# with the mined symptom (both `asdf./foo` and `asdf/foo` listed, expected
# only `asdf/foo`). If the pinned dependency versions do not reproduce the
# bug, this layer fails and the image is never built. Restore the tree to a
# pristine, exactly-parent state afterwards.
RUN su -s /bin/bash ubuntu -c 'set -e; cd /app/src; export PATH=/opt/cargo/bin:$PATH; \
    cp /opt/golden/regression.rs tests/regression.rs; \
    cargo test --no-run > /tmp/smoke.log 2>&1; \
    BIN=$(ls -t target/debug/deps/integration-* | grep -v "\.d$" | head -1); \
    "$BIN" --test-threads 1 r2990_trip_over_trailing_dot > /tmp/smoke-run.log 2>&1 || true; \
    grep -q "regression::r2990_trip_over_trailing_dot \.\.\. FAILED" /tmp/smoke-run.log; \
    grep -q "asdf./foo" /tmp/smoke-run.log; \
    git checkout -- tests/regression.rs; \
    test -z "$(git status --porcelain)"'
RUN echo "SMOKE OK: golden regression test fails at the parent commit inside this image"

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]