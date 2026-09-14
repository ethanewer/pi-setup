ARG UPSTREAM_SHA_PARENT=dbbc4c9a1e05ce37a94b3bf35fde29370429d312
ARG UPSTREAM_SHA_FIX=d28a3ee3d0f7122b0da64b0226d2e173e7d23747
ARG RUST_VERSION=1.98.1

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG RUST_VERSION

# The toolchain is the project's own rust-toolchain.toml revision, 1.98.1,
# pinned explicitly here (Cargo.lock does not pin the toolchain line). The
# toolchain lives in /opt (read-only for uid 1000); only /app and the cargo
# home bookkeeping under /opt/cargo are writable at trial time.
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates git pkg-config \
 && rm -rf /var/lib/apt/lists/*

# System-wide git trust (the trial may run as root or as uid 1000 and must
# be able to run git in the /app/src repo regardless of owner), and a
# committer identity for any build-time commits.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
#
# The tree is chowned to uid 1000 in the SAME layer that created it (the
# trial may run as root or as uid 1000), so no later chown layer copies the
# tree a second time (the size-hygiene duplication pattern).
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/astral-sh/uv.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && chown -R 1000:1000 /app/src

# Extract the project's own regression test for this bug (the test that the
# fix commit adds, crates/uv/tests/python/python_pin.rs at the fix commit)
# into /opt/golden using a THROWAWAY clone that is deleted immediately
# afterwards, so upstream test bytes never land in this task tree and the fix
# commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/astral-sh/uv.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:crates/uv/tests/python/python_pin.rs > /opt/golden/python_pin.rs \
 && test -s /opt/golden/python_pin.rs \
 && grep -q "python_pin_with_comments_and_whitespace" /opt/golden/python_pin.rs \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Install the toolchain (the project's own rust-toolchain.toml revision).
RUN curl -sSf https://sh.rustup.rs -o /tmp/rustup.sh \
 && sh /tmp/rustup.sh -y --default-toolchain none \
 && rustup toolchain install ${RUST_VERSION} \
 && rustup default ${RUST_VERSION} \
 && rustc --version && cargo --version \
 && rm -f /tmp/rustup.sh \
 && chmod -R a+rwX /opt/cargo

# WARM PASS, as uid 1000 in ONE layer so every warm artifact is stored once:
#   1. make the cargo home writable by the warm user (bookkeeping, registry
#      locks and crate extraction live under /opt/cargo),
#   2. compile the whole workspace plus the `uv` binary (dev profile),
#   3. compile the project's `python` test target,
#   4. PRUNE everything the trial rebuilds on demand anyway, and everything
#      the trial never recompiles:
#        - the relinkable binaries (target/debug/deps/uv-*, deps/uvx-*,
#          deps/python-*): the verifier deletes and relinks them by design,
#          and stripping the shipped `uv` binary keeps the first repro run
#          fast while the bytes stay tiny in the image;
#        - the object-dir copies `target/debug/libuv.rlib` (a content
#          duplicate of its deps/ entry);
#        - the rustc incremental caches of every crate OUTSIDE the rebuild
#          closure. A change to version_files.rs recompiles exactly the
#          workspace crates that (transitively) link uv-python. The caches
#          of the big crates on that path are kept (uv, uv-python,
#          uv-resolver, uv-cli, uv-distribution/-types): they are what
#          makes the ~70 s dev rebuild and ~120 s test build possible.
#          The remaining closure crates are small and full-compile fast,
#          and every crate outside the closure is never consulted at trial
#          time (cargo skips crates whose source and flags are unchanged),
#          so those bytes are dead weight. build-script outputs in
#          target/debug/build are regenerated by cargo on demand.
#   5. lock the toolchain back down (755 everywhere except the registry and
#      the bookkeeping files, which cargo needs to write at trial time) and
#      record sha256 pins of the toolchain binaries and of the golden
#      regression test so the verifier can detect substitution.
WORKDIR /app
RUN \
 su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
        cargo build -p uv > /tmp/warm1.log 2>&1'; rc=$?; \
    tail -5 /tmp/warm1.log; \
    if [ $rc -ne 0 ]; then echo "WARM DEV BUILD FAILED (exit $rc)"; exit $rc; fi; \
    test -x /app/src/target/debug/uv || { echo "no uv binary after warm dev build"; exit 1; } \
 && su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
        cargo test -p uv --test python --no-run > /tmp/warm2.log 2>&1'; rc=$?; \
    tail -8 /tmp/warm2.log; \
    if [ $rc -ne 0 ]; then echo "WARM TEST-BUILD FAILED (exit $rc)"; exit $rc; fi; \
    ls /app/src/target/debug/deps/ 2>/dev/null | grep -E '^python-' | head -3; \
    echo "(python test target present)" \
 && strip --strip-debug /app/src/target/debug/uv \
 && rm -f /app/src/target/debug/deps/uv-* /app/src/target/debug/deps/uvx-* \
        /app/src/target/debug/deps/python-* \
        /app/src/target/debug/libuv.rlib \
        /tmp/warm1.log /tmp/warm2.log \
 && find /app/src/target/debug/incremental -mindepth 1 -maxdepth 1 -type d \
        ! -name 'uv-*' ! -name 'uv_python-*' \
        ! -name 'uv_distribution*' ! -name 'uv_resolver-*' ! -name 'uv_cli-*' \
        -exec rm -rf {} + 2>/dev/null \
 && rm -rf /app/src/target/debug/build \
 && chmod 755 /opt/cargo /opt/cargo/bin \
 && find /opt/cargo/bin -type f -exec chmod 755 {} \; \
 && chmod 666 /opt/cargo/.global-cache /opt/cargo/.package-cache /opt/cargo/.package-cache-mutate 2>/dev/null || true \
 && mkdir -p /opt/pins \
 && sha256sum /opt/cargo/bin/cargo /opt/cargo/bin/rustc /usr/bin/git > /opt/pins/toolchain.sha256 \
 && sha256sum /opt/golden/python_pin.rs > /opt/pins/golden.sha256 \
 && chmod 555 /opt/pins /opt/golden \
 && chmod 444 /opt/pins/toolchain.sha256 /opt/pins/golden.sha256 /opt/golden/python_pin.rs \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && echo "toolchain + golden pinned" \
 && ls -la /app/src/target/debug/uv

# The trial runs at cpus=1; pin every cargo build the agent or the verifier
# triggers to a single CPU job. Warm layers above were built with the host's
# full parallelism, so this only throttles the trial.
RUN printf '[build]\njobs = 1\n' > /opt/cargo/config.toml \
 && grep -q "jobs = 1" /opt/cargo/config.toml \
 && echo "cargo jobs=1 configured"

ENV CARGO_BUILD_JOBS=1

COPY files/ /app/
RUN chmod a+rwX /app /app/src

CMD ["/bin/bash"]