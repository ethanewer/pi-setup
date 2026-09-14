ARG UPSTREAM_SHA_PARENT=5e81c60b35ce1481cdce5aa933b808faa71bc90e
ARG UPSTREAM_SHA_FIX=bc76a30c23317526441a76f99ff397f65acea607

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Base system tools for the toolchain installer, git and the build.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential pkg-config git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Rust toolchain 1.98.1 from the static.rust-lang.org dist tarball (the
# 2026-09-03 stable channel). rustup-init is no longer served on
# static.rust-lang.org and sh.rust-lang.org does not resolve on this network,
# so the dist tarball is the install path. Only rustc, the std and cargo are
# installed (no docs, clippy, rustfmt, analysis); /opt/rust doubles as
# CARGO_HOME, so its registry cache is co-located. The chown/chmod stay in
# this same RUN so the installed tree is written once and uid 1000 can write
# lock files at trial time without a copy-on-write duplication layer.
RUN start=$(date +%s) \
 && curl -s -o /tmp/rust.tar.xz https://static.rust-lang.org/dist/2026-09-03/rust-1.98.1-x86_64-unknown-linux-gnu.tar.xz \
 && cd /tmp \
 && tar -xJf rust.tar.xz \
 && ./rust-1.98.1-x86_64-unknown-linux-gnu/install.sh --prefix=/opt/rust \
      --without=rust-docs,rust-docs-json-preview,rustfmt-preview,rust-analyzer-preview,llvm-tools-preview,clippy-preview,rust-analysis-x86_64-unknown-linux-gnu,llvm-bitcode-linker-preview > /tmp/rustinstall.log 2>&1 \
 && end=$(date +%s) \
 && echo "rust toolchain install: $((end-start))s" \
 && rm -rf /tmp/rust.tar.xz /tmp/rust-1.98.1-x86_64-unknown-linux-gnu \
 && /opt/rust/bin/rustc --version \
 && /opt/rust/bin/cargo --version \
 && chown -R 1000:1000 /opt/rust \
 && chmod -R a+rwX /opt/rust

ENV PATH=/opt/rust/bin:$PATH \
    CARGO_HOME=/opt/rust \
    CARGO_BUILD_JOBS=1

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

# Warm RELEASE build at the parent commit, then the project's own integration
# suite (271 tests) must pass at the parent, all in one RUN; the ownership
# change for uid 1000 is folded into this SAME RUN so the layer is written
# once (a separate `chown -R` layer would duplicate every build artifact).
RUN cd /app/src \
 && start=$(date +%s) \
 && cargo build --release -j1 > /tmp/warmbuild.log 2>&1; rc=$?; end=$(date +%s); \
    echo "warm release build: $((end-start))s rc=$rc"; \
    tail -3 /tmp/warmbuild.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit 1; fi; \
    test -x /app/src/target/release/rg || { echo "rg binary missing"; exit 1; }; \
    start=$(date +%s); \
    cargo test --release -j1 > /tmp/parentsuite.log 2>&1; trc=$?; end=$(date +%s); \
    echo "parent integration suite: $((end-start))s rc=$trc"; \
    grep -q "test result: ok. 271 passed; 0 failed" /tmp/parentsuite.log \
      || { echo "PARENT SUITE DID NOT PASS 271"; tail -20 /tmp/parentsuite.log; exit 1; }; \
    test -z "$(git status --porcelain)" \
 && chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src \
 && chown -R 1000:1000 /opt/rust \
 && chmod -R a+rwX /opt/rust \
 && rm -rf /tmp/ripgrep-tests \
 && echo "warm build ok; parent suite green; tree owned by uid 1000"

# Bake a pristine PRE-FIX `rg` binary (built at the parent commit above) at
# /opt/prefix/rg. The verifier runs the agent's own reproduction and the
# hidden cases against this binary and requires them to FAIL, proving the
# symptom is real and that the checks target it.
RUN mkdir -p /opt/prefix \
 && cp /app/src/target/release/rg /opt/prefix/rg \
 && test -x /opt/prefix/rg \
 && chmod 755 /opt/prefix/rg

# Parent-direction confirmation in THIS exact image, as the uid-1000 user the
# trial may run as: the direct reproduction must panic with the assertion
# failure (exit nonzero). The warm build and the report that follows prove
# the trial path works for uid 1000 too.
RUN cat > /tmp/reprocheck.sh <<'SH'
#!/bin/bash
set -u
export HOME=/home/ubuntu
tmp=$(mktemp -d /tmp/reprocheck.XXXXXX) || exit 1
printf '\n##\n' > "$tmp/u.txt"
( cd "$tmp" && /app/src/target/release/rg -won '' u.txt ) > "$tmp/out" 2> "$tmp/err"
rc=$?
echo "direct repro rc=$rc"
cat "$tmp/out"
head -4 "$tmp/err"
if [ "$rc" -eq 0 ]; then echo "REPRO DID NOT CRASH - failing closed"; exit 1; fi
grep -q "assertion failed: self.start <= end" "$tmp/err" \
    || { echo "expected assertion message not seen in stderr"; exit 1; }
rm -rf "$tmp"
echo "parent direction: bug reproduces in this exact image as uid 1000"
SH
RUN chmod 755 /tmp/reprocheck.sh \
 && su -s /bin/bash ubuntu -c '/tmp/reprocheck.sh' \
 && rm -f /tmp/reprocheck.sh

# Extract the project's own regression test for this defect (r1891, appended
# to tests/regression.rs by the fix commit) into /opt/golden using a
# THROWAWAY clone that is deleted immediately afterwards, so the fix commit
# never lands in /app/src and no upstream test bytes enter this task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/BurntSushi/ripgrep.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/regression.rs \
      > /opt/golden/regression.rs \
 && test -s /opt/golden/regression.rs \
 && grep -q "rgtest!(r1891" /opt/golden/regression.rs \
 && grep -q "issues/1891" /opt/golden/regression.rs \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && echo "golden regression.rs extracted from the fix commit"

# Fix-direction confirmation in THIS exact image, using a SECOND throwaway
# clone of the fix commit (deleted afterwards): build it, and the project's
# own r1891 regression test must pass, proving the oracle direction works
# with this toolchain and this image before the task is shipped.
RUN git init -q /tmp/fixcheck \
 && cd /tmp/fixcheck \
 && git remote add origin https://github.com/BurntSushi/ripgrep.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_FIX}" \
 && start=$(date +%s) \
 && cargo build --release -j1 > /tmp/fixcheck-build.log 2>&1; rc=$?; end=$(date +%s); \
    echo "fix tree build: $((end-start))s rc=$rc"; \
    if [ $rc -ne 0 ]; then tail -20 /tmp/fixcheck-build.log; exit 1; fi; \
    cargo test --release -j1 -- r1891 > /tmp/fixcheck-test.log 2>&1; trc=$?; \
    echo "r1891 at fix commit rc=$trc"; \
    if [ $trc -ne 0 ]; then tail -30 /tmp/fixcheck-test.log; exit 1; fi; \
    grep -q "test regression::r1891 ... ok" /tmp/fixcheck-test.log \
      || { echo "r1891 did not run/pass"; tail -30 /tmp/fixcheck-test.log; exit 1; }; \
    grep -q "1 passed" /tmp/fixcheck-test.log \
      || { echo "r1891 did not report 1 passed"; tail -30 /tmp/fixcheck-test.log; exit 1; }; \
    chown -R 1000:1000 /opt/rust \
 && chmod -R a+rwX /opt/rust \
 && rm -rf /tmp/ripgrep-tests \
 && cd / \
 && rm -rf /tmp/fixcheck \
 && echo "fix direction: r1891 passes with this toolchain; clone deleted"

# Belt: prove the fix commit is not reachable from the trial clone. The
# object store holds exactly one commit (the parent), so both the commit
# object and every blob changed by the fix are absent.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# Record sha256 pins of the golden regression test, of the pre-fix binary,
# and of the build/test toolchain itself, so the verifier can detect
# substitution. The trial and the verifier both run the compiled binary and
# the project's own test suite; an adversarial root agent could otherwise
# swap the compiler or the test shell for a stub that fakes a green run.
# /opt is read-only for everyone afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/regression.rs > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/rg > /opt/pins/prefix-rg.sha256 \
 && sha256sum /opt/rust/bin/rustc /opt/rust/bin/cargo \
              /usr/bin/gcc /usr/bin/cc /usr/bin/make /usr/bin/git \
              /usr/bin/bash /usr/bin/cat /usr/bin/grep /usr/bin/od \
              /usr/bin/cmp /usr/bin/diff \
      > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/regression.rs \
 && test "$(wc -l < /opt/pins/toolchain.sha256)" = 12 \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-rg.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + prefix binary + toolchain pinned"

COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/README-BUILD.md

WORKDIR /app

CMD ["/bin/bash"]