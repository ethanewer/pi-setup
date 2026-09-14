# cutwater-swell: real upstream checkout of BurntSushi/ripgrep at the parent
# commit of upstream fix 9d738ad (issue #2884) — an inner-literal-extraction
# false negative. The trial runs with no network and one CPU; everything is
# baked in at build time.
ARG UPSTREAM_SHA_PARENT=6c5108ed17987531644518fac8c1659b0b202611
ARG UPSTREAM_SHA_FIX=9d738ad0c009e6632d75fa3d36051e5ae7f7cce6
ARG RUST_DIST_DATE=2026-09-03
ARG RUST_VER=1.98.1

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG RUST_DIST_DATE
ARG RUST_VER

# Pure-Rust build; the linker still needs a C toolchain. `git` for the clone.
ENV CARGO_HOME=/opt/cargo
ENV PATH=/opt/rust/bin:$PATH
ENV CARGO_BUILD_JOBS=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential git curl ca-certificates python3 \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Rust 1.98.1 from the official dist tarball, pinned by both URL date and
# version (static.rust-lang.org no longer serves rustup-init; this is the
# mining container's recipe). Fail closed on a version drift.
RUN curl -sO https://static.rust-lang.org/dist/${RUST_DIST_DATE}/rust-${RUST_VER}-x86_64-unknown-linux-gnu.tar.xz \
 && tar xf rust-${RUST_VER}-x86_64-unknown-linux-gnu.tar.xz \
 && ./rust-${RUST_VER}-x86_64-unknown-linux-gnu/install.sh \
      --prefix=/opt/rust --components=rustc,cargo,rust-std-x86_64-unknown-linux-gnu \
      > /dev/null \
 && rm -rf rust-${RUST_VER}-x86_64-unknown-linux-gnu rust-${RUST_VER}-x86_64-unknown-linux-gnu.tar.xz \
 && test "$(/opt/rust/bin/rustc --version)" = "rustc 1.98.1 (48a229cea 2026-09-01)" \
 && /opt/rust/bin/cargo --version \
 && echo "rust pinned ok"

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
 && test "$(git rev-list --all --count)" = "1" \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# Warm build at the parent commit (~1 minute on one core): a full debug
# build plus the grep-regex unit suite, so the agent's own cargo runs are
# incremental and fully offline, and so the unit-suite expectations are
# proven green at the pinned commit. Also bakes a pristine PRE-FIX binary at
# /opt/prefix/rg. The ownership chmods run in the SAME layer as the build so
# the image never stores the tree / cache twice (copy-on-write).
RUN cd /app/src \
 && cargo build > /tmp/warm-build.log 2>&1; rc=$?; tail -3 /tmp/warm-build.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit 1; fi \
 && test -x target/debug/rg && echo "warm debug build ok" \
 && cargo test -p grep-regex --lib > /tmp/warm-test.log 2>&1; rc=$?; tail -3 /tmp/warm-test.log; \
    if [ $rc -ne 0 ]; then echo "WARM LIB TESTS FAILED (exit $rc)"; exit 1; fi \
 && grep -q "24 passed" /tmp/warm-test.log \
 && mkdir -p /opt/prefix \
 && cp target/debug/rg /opt/prefix/rg \
 && chmod -R a+rwX /opt/cargo /app/src \
 && chmod 755 /opt/prefix/rg \
 && chmod 555 /opt/prefix \
 && rm -f /tmp/warm-build.log /tmp/warm-test.log \
 && echo "warm build ok, pre-fix binary baked"

# The trial has no network; every crate is cached in /opt/cargo.
ENV CARGO_NET_OFFLINE=true

# Parent-direction confirmation 1/2 in THIS image: the direct reproduction,
# run as uid 1000 (the user the trial may run as). The bug must reproduce
# with THIS Rust toolchain and THIS pinned Cargo.lock, or the task's oracle
# could never pass.
RUN cat > /tmp/reprocheck.sh <<'SH'
#!/bin/bash
set -u
export PATH=/opt/rust/bin:$PATH CARGO_NET_OFFLINE=true
work=$(mktemp -d /tmp/reprocheck.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
printf 'e-x\n' > "$work/f"
out=$(/app/src/target/debug/rg '(?i:e.x|ex)' "$work/f" 2>&1); rc=$?
echo "repro rc=$rc out=[$out]"
if [ "$rc" -eq 0 ]; then echo "REPRO DID NOT FAIL AT PARENT - failing closed"; exit 1; fi
[ -z "$out" ] || { echo "unexpected output at parent: [$out]"; exit 1; }
echo "parent-direction: bug reproduces in this exact image"
SH
RUN chmod 755 /tmp/reprocheck.sh \
 && su -s /bin/bash ubuntu -c '/tmp/reprocheck.sh' \
 && rm -f /tmp/reprocheck.sh

# Extract the project's own regression test for this bug (the
# `case_insensitive_alternation` unit test in crates/regex/src/literal.rs
# appended by the fix commit) into /opt/golden using a THROWAWAY clone that
# is deleted immediately afterwards, so the fix object never lands in
# /app/src and no upstream test bytes enter this task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/BurntSushi/ripgrep.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:crates/regex/src/literal.rs \
      | grep -B1 -A3 -E 'fn case_insensitive_alternation' \
      > /opt/golden/case_insensitive_alternation.rs \
 && grep -q '#\[test\]' /opt/golden/case_insensitive_alternation.rs \
 && grep -q 'fn case_insensitive_alternation' /opt/golden/case_insensitive_alternation.rs \
 && grep -q 'I("X"), I("x")' /opt/golden/case_insensitive_alternation.rs \
 && test "$(wc -l < /opt/golden/case_insensitive_alternation.rs)" = "5" \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && echo "golden regression test extracted"

# Golden-direction confirmation in THIS image: plant the golden regression
# test into a fresh clone of the PARENT tree and require it to FAIL there.
# If it does not fail, the planted test does not measure the real defect.
RUN cat > /tmp/gc.py <<'PY'
import sys
lit = '/tmp/golden-check/crates/regex/src/literal.rs'
text = open(lit).read().rstrip('\n')
assert text.endswith('}'), "literal.rs does not end with the tests-module close"
gold = open('/opt/golden/case_insensitive_alternation.rs').read().rstrip('\n')
text = text[:-1] + '\n' + gold + '\n}\n'
open(lit, 'w').write(text)
print("golden planted into parent clone")
PY
RUN mkdir -p /tmp/golden-check \
 && git -C /app/src archive HEAD | tar -x -C /tmp/golden-check \
 && python3 /tmp/gc.py \
 && cd /tmp/golden-check \
 && cargo test -p grep-regex --lib case_insensitive_alternation \
      > /tmp/golden-check.log 2>&1; rc=$?; tail -8 /tmp/golden-check.log; \
    if [ "$rc" -eq 0 ]; then echo "ERROR: golden regression test PASSED at parent"; exit 1; fi \
 && grep -q "FAILED" /tmp/golden-check.log \
 && grep -q 'E("EX")' /tmp/golden-check.log \
 && cd / \
 && rm -rf /tmp/golden-check /tmp/golden-check.log /tmp/gc.py \
 && echo "golden-direction ok: regression test fails at parent in this image"

# Belt: prove the fix commit is not reachable from the trial clone, and that
# HEAD is still the pinned parent.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test "$(git rev-list --all --count)" = "1" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# Record sha256 pins of the golden regression test, of the pre-fix binary,
# and of the toolchain, so the verifier can detect substitution. The trial
# and the verifier both execute the compiled binary and cargo; an
# adversarial root agent could otherwise swap the compiler or the pre-fix
# binary for a stub that fakes a green run. /opt is made read-only for
# everyone afterwards; the verifier re-checks the pins before use.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/case_insensitive_alternation.rs > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/rg > /opt/pins/prefix-rg.sha256 \
 && sha256sum /opt/rust/bin/rustc /opt/rust/bin/cargo /usr/bin/gcc /usr/bin/cc \
              /usr/bin/git /usr/bin/bash /usr/bin/python3 \
      > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/case_insensitive_alternation.rs \
 && chmod 555 /opt/prefix/rg \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-rg.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + pre-fix binary + toolchain pinned"

# Permissions for uid 1000 were already set in the warm-build RUN (same layer
# as the build, so nothing is stored twice): /app/src and /opt/cargo are
# a+rwX there and nothing later restricts them. /opt is pinned read-only in
# the pins RUN. No tree-wide chmod in its own layer (copy-on-write dup).
COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/README-BUILD.md

WORKDIR /app

CMD ["/bin/bash"]