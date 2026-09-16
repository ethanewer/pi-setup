ARG UPSTREAM_SHA_PARENT=7f1b1471d5e3f88087eaad77885dc70968750bb3
ARG UPSTREAM_SHA_FIX=8dfa67a245b08a2c0ea1e6381c0086768470f317

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH="/opt/cargo/bin:${PATH}"

# C toolchain needed to link the Rust binary (rust-lld needs libc crt objects
# and -lutil/-lrt, so libc6-dev is required), plus curl for rustup and git for
# the build-time clone. Then set up system-wide git safety + identity so the
# tree works for root and uid 1000 alike.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gcc make curl libc6-dev \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Rust toolchain straight into /opt (rustup 1.98.1 / stable 1.98.1, minimal
# profile: rustc + cargo only). The chown happens in the SAME RUN so the
# toolchain is not duplicated across layers. /opt/rustup + /opt/cargo end up
# owned by uid 1000; the trial (root or uid 1000) can use them either way.
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal \
 && chown -R 1000:1000 /opt/rustup /opt/cargo \
 && rustc --version \
 && cargo --version

# Clone the REAL upstream repository (sharkdp/fd) at exactly the parent commit
# with the shallowest possible history: `git init` + one depth-1 fetch of the
# pinned SHA means the object store in /app/src holds ONLY the parent commit.
# The fix commit (which an agent must not be able to look up or fetch) is
# NEVER fetched into this clone; it is asserted unreachable below. The clone
# is created AS uid 1000 so every file in /app/src is owned by uid 1000 from
# the start (no later chown layer, no copy-on-write duplication).
RUN mkdir -p /app && chown 1000:1000 /app \
 && echo ${UPSTREAM_SHA_PARENT} > /tmp/parent.sha \
 && su -p -s /bin/bash ubuntu -c 'export PATH=/opt/cargo/bin:$PATH HOME=/home/ubuntu; P=$(cat /tmp/parent.sha) && git init -q /app/src && cd /app/src \
      && git remote add origin https://github.com/sharkdp/fd.git \
      && git fetch --depth 1 origin $P \
      && git checkout -q --detach FETCH_HEAD \
      && test "$(git rev-parse HEAD)" = "$P" \
      && echo "parent pin ok: $(git rev-parse HEAD)"'

# Warm build at the parent commit. The trial has no network, so this layer IS
# the warm tree: the agent edits one source file and an incremental `cargo
# build -j1` takes only seconds. Fail closed if the build fails.
RUN su -p -s /bin/bash ubuntu -c 'export PATH=/opt/cargo/bin:$PATH HOME=/home/ubuntu; cd /app/src \
 && cargo build -j1 > /tmp/warm-build.log 2>&1; rc=$?; \
    [ $rc -ne 0 ] && { echo "WARM BUILD FAILED rc=$rc"; tail -30 /tmp/warm-build.log; exit 1; }; \
    test -x target/debug/fd \
 && echo "warm build ok"'

# Warm the integration-test harness (tests/tests.rs is a large file; compiling
# it is the expensive part of the first `cargo test`, a few minutes at 1 CPU).
# After this layer the verifier's harness rebuilds are incremental, and the
# agent can run the project test suite without a long first compile.
RUN su -p -s /bin/bash ubuntu -c 'export PATH=/opt/cargo/bin:$PATH HOME=/home/ubuntu; cd /app/src \
 && cargo test --no-run -j1 > /tmp/warm-test.log 2>&1; rc=$?; \
    [ $rc -ne 0 ] && { echo "WARM TESTNORUN FAILED rc=$rc"; tail -30 /tmp/warm-test.log; exit 1; }; \
    echo "warm test harness ok"'

# Bake a pristine PRE-FIX `fd` binary (built at the parent commit above) at
# /opt/prefix/fd. The verifier runs the agent's own reproduction and the
# hidden cases against this binary and requires them to FAIL, proving the
# symptom is real and that each case targets it. sha256-pinned later.
RUN mkdir -p /opt/prefix \
 && cp /app/src/target/debug/fd /opt/prefix/fd \
 && test -x /opt/prefix/fd \
 && echo "pre-fix binary baked"

# Extract the project's own regression test for this bug (test_single_dash_root_path,
# added by the fix commit to tests/tests.rs) into /opt/golden using a THROWAWAY
# clone that is rm -rf'd immediately afterwards, so the fix commit never lands
# in /app/src and no fix-commit bytes enter this task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/sharkdp/fd.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/tests.rs > /opt/golden/tests.rs \
 && test -s /opt/golden/tests.rs \
 && grep -q "test_single_dash_root_path" /opt/golden/tests.rs \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && echo "golden test extracted; fix clone deleted"

# Belt: prove the fix commit is not reachable from the trial clone. The object
# store holds exactly one commit (the parent), so both the commit object and
# every blob changed by the fix are absent.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# Record sha256 pins of the golden test, of the pre-fix binary, and of the
# build toolchain itself, so the verifier can detect substitution. /opt is
# read-only for everyone afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/tests.rs > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/fd > /opt/pins/prefix-fd.sha256 \
 && sha256sum /opt/cargo/bin/rustc /opt/cargo/bin/cargo /usr/bin/gcc /usr/bin/git /usr/bin/bash \
      > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/tests.rs \
 && test "$(wc -l < /opt/pins/toolchain.sha256)" = 5 \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-fd.sha256 >/dev/null \
 && echo "golden + prefix binary + toolchain pinned"

# The trial has no network. From here on cargo is forced fully offline so the
# agent and the verifier behave deterministically against the warm caches
# (registry index + crate sources + dependency builds are all already in the
# image; a fix cannot add a dependency). The smoke build below proves the warm
# cache is complete even for a real (non-noop) compile.
ENV CARGO_NET_OFFLINE=true

RUN su -p -s /bin/bash ubuntu -c 'export PATH=/opt/cargo/bin:$PATH HOME=/home/ubuntu; cd /app/src \
 && touch src/cli.rs \
 && cargo build -j1 > /tmp/offline-smoke.log 2>&1; rc=$?; \
    [ $rc -ne 0 ] && { echo "OFFLINE SMOKE FAILED rc=$rc"; tail -30 /tmp/offline-smoke.log; exit 1; }; \
    git checkout -q -- src/cli.rs; \
    git status --porcelain > /tmp/smoke-status.txt; \
    [ -s /tmp/smoke-status.txt ] && { echo "SMOKE DIRTIED THE TREE"; exit 1; }; \
    echo "offline smoke ok: full offline rebuild works"'

COPY files/ /app/
RUN chmod 644 /app/README-BUILD.md

WORKDIR /app

CMD ["/bin/bash"]