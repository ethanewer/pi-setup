# ---------------------------------------------------------------------------
# capstan-brackish: fd panics on an out-of-range '@' Unix timestamp in
# --changed-before / --changed-within instead of rejecting it gracefully.
#
# The image clones sharkdp/fd and checks out upstream PARENT commit
# fb0426fed164c5fa9cd04b5e4aa8d8c375efa1d0 (the test-first commit immediately
# before upstream commit 5becb9d52cb532c35b68421075e4d8ee8d6c77cd fixed issue
# #2081), so the agent gets the real repository with the real bug still in it,
# including the project's own failing regression test.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. The golden-test extraction below uses a
# throwaway clone that is deleted, so the fix bytes never land in the working
# clone either.
#
# Rust: fd at this commit is rust 2024 edition, MSRV 1.90.0; the tree uses the
# reorganized standard library (std::time::SystemTime etc.) that only ships in
# newer toolchains, so the distro rustc (1.75) cannot build it. A pinned
# toolchain 1.98.1 (the version the behavior was verified against) is installed
# via rustup at build time. The project's committed Cargo.lock pins all 130+
# crates.io dependencies; the full dependency graph (including dev-dependencies
# needed by `cargo test`) is downloaded and compiled once in this Dockerfile,
# so trial-time builds are incremental and fully offline
# (CARGO_NETWORK=off, and the trial container has no network anyway).
# ---------------------------------------------------------------------------
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=fb0426fed164c5fa9cd04b5e4aa8d8c375efa1d0
ARG FIX_SHA=5becb9d52cb532c35b68421075e4d8ee8d6c77cd
ARG RUST_VERSION=1.98.1

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:${PATH}

# ---- C toolchain: several crates in the dependency graph (rustix, libc,
#      quote, ...) have build scripts that need a system `cc` linker ---------
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*

# ---- pinned Rust toolchain (installed outside any $HOME so it works for
#      root and for uid 1000 alike; set only the version-pinned default) ------
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain "${RUST_VERSION}" --profile minimal \
 && rustup default "${RUST_VERSION}" \
 && rustc --version \
 && cargo --version \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && chmod -R a+rwX /opt/rustup /opt/cargo

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/sharkdp/fd.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && chmod -R a+rwX /app/src

# ---- extract the upstream regression test source from the FIX commit --------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes also never enter this repository. The golden
# file lives only in the image at /opt/golden/ and deliberately contains ONLY
# the regression test function (its '#[test]' attribute line and body), never
# the surrounding source -- this is exactly what the tree already contains, and
# it must NOT contain the fixed code, or the image would hand the agent the
# answer. The awk below must stay byte-identical to extract_test in
# tests/test.sh. The integrity check that the fix commit really contains the
# checked_add fix is performed against the commit's file without baking it in.
RUN git clone --depth 1 --no-checkout https://github.com/sharkdp/fd.git /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && { git show ${FIX_SHA}:src/filter/time.rs \
      | awk '/fn out_of_range_unix_timestamp_is_rejected\(\) \{/ { if (prev ~ /#\[/) print prev; on=1 } on { print } on && /^    \}$/ { exit } { prev=$0 }' \
      | sed 's/[[:space:]]*$//'; } > /opt/golden/time.test.txt \
 && test -s /opt/golden/time.test.txt \
 && grep -q "fn out_of_range_unix_timestamp_is_rejected" /opt/golden/time.test.txt \
 && grep -q '#\[test\]' /opt/golden/time.test.txt \
 && ! grep -q "checked_add" /opt/golden/time.test.txt \
 && git show ${FIX_SHA}:src/filter/time.rs | grep -q "checked_add" \
 && cd / && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/time.test.txt

# ---- warm the cargo cache and prebuild everything (network used here) -------
# `cargo test --no-run` compiles both test executables (the unit-test binary
# and the self-contained integration harness in tests/) without running them,
# so the trial's `cargo test` invocations are incremental. The regression test
# fails at this commit by design; that is why the build must not run it here.
RUN cd /app/src \
 && cargo build \
 && cargo test --no-run \
 && chmod -R a+rwX /app/src /opt/cargo

# ---- from here on the trial must behave exactly as it will offline ----------
ENV CARGO_NETWORK=off

WORKDIR /app

COPY files/ /app/

RUN chmod a+rwX /app /app/probe_out_of_range_ts.sh \
 && chmod -R a+rwX /opt/golden \
 && find /opt/golden -type f -exec chmod a+r {} +

CMD ["/bin/bash"]