# dunnage-light: clap-rs/clap at the parent of upstream issue #3815
#
# The image clones clap-rs/clap SHALLOW at the PARENT commit (the real bug is
# present in the working tree), prebuilds the project's own test harness so
# the trial works fully offline, and snapshots a pristine copy of the parent
# state into /opt/pristine for the verifier's pre-fix check. The project's
# own regression test for the bug is shipped in the task tree at
# tests/golden/arg_settings.rs (mounted only at verifier time, never visible to
# the agent), and its authenticity is asserted at build time against the FIX
# commit via a throwaway bare clone that is deleted, so the fix object is never
# reachable from /app/src or /opt/pristine. The golden test is deliberately NOT
# part of the image: the agent must author its own failing reproduction as a
# deliverable.
#
# Dependency pin from the mined entry: rust 1.98.1 (rustup-installed, then
# copied under /opt so the uid-1000 trial can execute it without touching
# /root). CARGO_HOME is a writable image copy of the registry cache, because
# the trial is offline and cargo must never need the network.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=8bb3853eb5e19e9190d142ebb9ae230312da89f1
ARG FIX_SHA=3eacf5b8b0f1e79955a0e7f94dc18b1f6a6b6502
ARG GOLDEN_SHA=08a1fc63f7f4c4b3936c4353e18d869c1e64c439b3ac64615011fa5c5bc78778

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- build toolchain: rust 1.98.1, pinned ------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

RUN curl -sSf https://sh.rustup.rs -o /tmp/rustup.sh \
 && sh /tmp/rustup.sh -y --default-toolchain stable \
 && /root/.cargo/bin/rustup toolchain install 1.98.1 \
 && /root/.cargo/bin/rustup default 1.98.1

# Everything rust needs stays under /root: the trial and verifier both run as
# root in this suite (empirically confirmed), so no world-writable copies are
# needed; PATH points straight at the pinned toolchain's real binaries.
ENV CARGO_HOME=/root/.cargo \
    PATH="/root/.rustup/toolchains/1.98.1-x86_64-unknown-linux-gnu/bin:$PATH"

# ---- working clone: buggy parent commit, fix commit unreachable -------------
RUN git clone --depth 1 https://github.com/clap-rs/clap.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 8bb3853eb5e19e9190d142ebb9ae230312da89f1 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && test -z "$(git status --porcelain)" \
 && ! grep -rn --include='*.rs' 'fn default_value_ifs_os' tests/ \
 && git config --system --add safe.directory '/app/src'

# ---- prebuild the project's own test harness (cached layers) ----------------
# Cold-compiles the dependency graph into /app/src/target and fills the
# CARGO_HOME registry cache. The run proves the pinned parent state is fully
# green: the builder suite baseline is 1576 passing tests.
RUN cd /app/src \
 && cargo test --no-run -p clap \
 && BIN=$(ls -t target/debug/deps/builder-* | grep -v '\.d$' | head -1) \
 && "$BIN" > /tmp/smoke.log 2>&1 \
 && grep -q 'test result: ok. 1576 passed' /tmp/smoke.log

# ---- pristine pre-fix snapshot for the verifier ------------------------------
# A second copy of the parent state (including its warm target dir). The
# verifier runs the agent's own reproduction against it and requires the
# reproduction (and the upstream golden regression test) to FAIL there.
RUN cp -a /app/src /opt/pristine \
 && cd /opt/pristine \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && test -z "$(git status --porcelain)" \
 && grep -Fq 'self.default_value_if_os(arg.key(), *val, *default);' src/builder/arg.rs \
 && git config --system --add safe.directory '/opt/pristine'

# ---- verify the upstream regression test resolves to what the task ships ---
# The golden test (tests/builder/arg_settings.rs at the FIX commit) is shipped in
# the task tree under tests/golden/ and mounted only at verifier time (never
# visible to the agent during the trial, which must author its own failing
# reproduction). This build step fetches the FIX commit into a throwaway bare
# clone, asserts that its arg_settings.rs byte-hashes to GOLDEN_SHA (so the
# shipped golden is provably the fix commit's own regression test), then deletes
# the clone. The golden is deliberately NOT persisted into the image, so the fix
# object and the reproduction are unreachable from /app/src, /opt/pristine, and
# the rest of the trial container.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/clap-rs/clap.git \
 && git fetch --depth 1 origin 3eacf5b8b0f1e79955a0e7f94dc18b1f6a6b6502 \
 && test -n "$(git show 3eacf5b8b0f1e79955a0e7f94dc18b1f6a6b6502:tests/builder/arg_settings.rs 2>/dev/null)" \
 && grep -Fq 'fn default_value_ifs_os' <(git show 3eacf5b8b0f1e79955a0e7f94dc18b1f6a6b6502:tests/builder/arg_settings.rs) \
 && test "$(git show 3eacf5b8b0f1e79955a0e7f94dc18b1f6a6b6502:tests/builder/arg_settings.rs | sha256sum | cut -d' ' -f1)" = "$GOLDEN_SHA" \
 && cd / && rm -rf /tmp/fixsrc

# The trees are root-owned and the trial/verifier run as root, so nothing
# more is needed here.

WORKDIR /app

CMD ["/bin/bash"]