# ---------------------------------------------------------------------------
# chainplate-foresheet: fd dies with an unhandled panic when the working
# directory it was launched from is removed while the search is still
# running (upstream issue #1900), instead of finishing, skipping or
# reporting the problem.
#
# The image clones sharkdp/fd and checks out upstream PARENT commit
# 7027d45303b412be6fa9c09d689cc6276748fb38 (fd v10.4.2), so the agent gets
# the real repository with the real bug still in it. With --full-path, fd
# resolves every entry to an absolute path via filesystem::path_absolute_form
# (src/walk.rs), which calls env::current_dir(); once the cwd has been
# unlinked, that returns NotFound and the `.expect("Retrieving absolute path
# succeeds")` at src/walk.rs:528-529 panics the whole process (exit 101).
# Launching from a directory that is already gone at startup is handled
# gracefully; it is the directory being REMOVED MID-SEARCH that aborts the
# run, for every remaining matched file.
#
# The clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>`, so the ONLY commit object in /app/src is the parent
# itself; the fix commit (d3a500af...) is never fetched into /app/src and a
# build-time assertion confirms it is absent. The upstream regression test
# full_path_search_returns_error_for_invalid_cwd lives in src/walk.rs at the
# FIX commit only (it compiles only there, because it references the new
# search_str_for_entry helper), so the TEST MODULE (and only the test module
# -- never the fix implementation) is extracted from the fix commit into
# /opt/golden/tests-module.rs using a throwaway clone under /tmp which is
# deleted immediately afterwards; the fix bytes never land in the working
# clone and never enter this task's repository. The image must not let the
# agent read the fixing source: the golden artifact contains the regression
# test alone, with hard guards asserting the fix implementation lines
# (WorkerResult::FatalError, the search_str_for_entry definition) are NOT in
# it.
#
# Both directions are re-confirmed INSIDE this image at build time (evidence
# captured in /opt/fixcheck/ and deleted before the image is finalised):
#   parent: the CLI repro (cwd removed mid-walk over a large tree) panics,
#           exit 101;
#   fix:    the golden unit test passes via `cargo test
#           full_path_search_returns_error_for_invalid_cwd` in the throwaway
#           fix-checkout, and the same CLI repro exits 1 without panicking
#           (run twice).
# The throwaway fix checkout is deleted before the byte layer is finalized.
# /opt/fixcheck (the captured evidence logs) is likewise removed from the
# final image: it names the golden test and the expected outcomes, which the
# agent must discover by debugging, not by reading the image.
#
# Rust: fd at this commit is rust 2024 edition, MSRV 1.90.0; the distro
# rustc (1.75) cannot build it. A pinned toolchain 1.98.1 (the version the
# behaviour was verified against) is installed via rustup outside any $HOME.
# The project's committed Cargo.lock pins all crates.io dependencies
# (tempfile 3.24 is already a dev-dependency, so the golden test needs no new
# dependency); the full dependency graph including dev-dependencies needed by
# `cargo test` is downloaded and compiled once in this Dockerfile, so
# trial-time builds are incremental and fully offline (CARGO_NETWORK=off, and
# the trial container has no network anyway).
# ---------------------------------------------------------------------------
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=7027d45303b412be6fa9c09d689cc6276748fb38
ARG FIX_SHA=d3a500af7aee3a9f099b09e1831da3fc39980c61
ARG RUST_VERSION=1.98.1

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:${PATH}

# ---- C toolchain + curl for rustup + procps for pgrep (the CLI repro's
#      background deleter waits for the fd process to appear) ----------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential curl ca-certificates git procps \
 && rm -rf /var/lib/apt/lists/*

# ---- pinned Rust toolchain (in /opt so it works for root and uid 1000) -----
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain "${RUST_VERSION}" --profile minimal \
 && rustup default "${RUST_VERSION}" \
 && rustc --version \
 && cargo --version \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/sharkdp/fd.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression TEST MODULE from the FIX commit -------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git, and upstream bytes never enter this task's repository; the
# golden artifact (the fix commit's walk.rs tests module ONLY -- never the
# fixed implementation) lives only in the image at /opt/golden/tests-module.rs
# with a+r perms. The exclusion guards fail the build if any fixing source
# (the FatalError variant or the search_str_for_entry definition) slips into
# the artifact: the agent must not be handed the fix inside the image.
RUN mkdir -p /opt/golden /opt/fixcheck \
 && git init -q /tmp/fixgolden \
 && git -C /tmp/fixgolden remote add origin https://github.com/sharkdp/fd.git \
 && git -C /tmp/fixgolden fetch --depth 1 origin ${FIX_SHA} \
 && git -C /tmp/fixgolden checkout -q --detach FETCH_HEAD \
 && git -C /tmp/fixgolden show ${FIX_SHA}:src/walk.rs > /tmp/fixgolden/walk.rs \
 && awk '/^#\[cfg\(test\)\]$/{p=1} p' /tmp/fixgolden/walk.rs > /opt/golden/tests-module.rs \
 && test -s /opt/golden/tests-module.rs \
 && test "$(head -1 /opt/golden/tests-module.rs)" = "#[cfg(test)]" \
 && grep -q "fn full_path_search_returns_error_for_invalid_cwd" /opt/golden/tests-module.rs \
 && grep -q "use super::search_str_for_entry" /opt/golden/tests-module.rs \
 && ! grep -q "WorkerResult::FatalError" /opt/golden/tests-module.rs \
 && ! grep -q "fn search_str_for_entry<'a>" /opt/golden/tests-module.rs \
 && chmod a+r /opt/golden/tests-module.rs \
 && rm -rf /tmp/fixgolden

# ---- the agent-side reproducer script (copied early so the build-time
#      both-directions re-confirmation uses exactly the same probe) ----------
WORKDIR /app
COPY files/ /app/
RUN chmod +x /app/probe_cwd_removed.sh

# ---- warm the cargo cache and prebuild everything (network used here) ------
# `cargo test --no-run` compiles both test executables (the unit-test binary
# and the self-contained integration harness in tests/) without running them,
# so the trial's `cargo test` invocations are incremental. The regression
# test does not exist at this commit by design -- the fix-side confirmation
# of the golden test happens in the throwaway fix checkout below.
RUN cd /app/src \
 && cargo build \
 && cargo test --no-run

# ---- re-confirm direction 1 (parent): the CLI repro must PANIC -------------
RUN set +e \
 && FD_PROBE_N=600000 bash /app/probe_cwd_removed.sh > /opt/fixcheck/parent-cli.txt 2>&1; rc=$?; set -e \
 && echo "parent probe exit = $rc (1 means bug present: panic observed)" >> /opt/fixcheck/parent-cli.txt \
 && test "$rc" = "1"

# ---- re-confirm direction 2 (fix): golden unit test passes, CLI graceful ---
# Throwaway checkout of the FIX commit, built into its OWN target directory so
# the prebuilt artifacts under /app/src/target are never polluted by the fix
# build (a shared CARGO_TARGET_DIR would leave a fixed binary behind in the
# image -- the trial must ship parent-built artifacts so the agent reproduces
# the bug on its first run). Deleted afterwards: no copy of the fixed tree
# (and no history of it) remains in the image.
RUN git init -q /tmp/fixcheck \
 && git -C /tmp/fixcheck remote add origin https://github.com/sharkdp/fd.git \
 && git -C /tmp/fixcheck fetch --depth 1 origin ${FIX_SHA} \
 && git -C /tmp/fixcheck checkout -q --detach FETCH_HEAD \
 && test "$(git -C /tmp/fixcheck rev-parse HEAD)" = "${FIX_SHA}" \
 && cd /tmp/fixcheck \
 && cargo test --quiet full_path_search_returns_error_for_invalid_cwd > /opt/fixcheck/fix-golden-test.txt 2>&1 \
 && grep -q "1 passed; 0 failed" /opt/fixcheck/fix-golden-test.txt \
 && cargo build > /tmp/fixcheck-build.log 2>&1 \
 && set +e \
 && FD_BIN=/tmp/fixcheck/target/debug/fd FD_PROBE_N=600000 bash /app/probe_cwd_removed.sh > /opt/fixcheck/fix-cli-run1.txt 2>&1; rc1=$?; set -e \
 && set +e \
 && FD_BIN=/tmp/fixcheck/target/debug/fd FD_PROBE_N=600000 bash /app/probe_cwd_removed.sh > /opt/fixcheck/fix-cli-run2.txt 2>&1; rc2=$?; set -e \
 && echo "fix probe exit (run1) = $rc1 ; (run2) = $rc2 (0 = graceful exit 1 without panic)" >> /opt/fixcheck/fix-cli-run2.txt \
 && test "$rc1" = "0" \
 && test "$rc2" = "0" \
 && rm -rf /tmp/fixcheck \
 && cd /app/src \
 && cargo build > /dev/null 2>&1 \
 && cargo test --no-run > /dev/null 2>&1

# ---- from here on the trial must behave exactly as it will offline ----------
ENV CARGO_NETWORK=off

WORKDIR /app

# The /opt/fixcheck evidence logs are removed from the FINAL image: the agent
# runs inside this image and must learn the golden test's name and the
# expected outcomes by debugging, not by reading the build-time captures.
# (They have served their purpose: the RUN steps above already asserted both
# directions, and the wave report quotes them.)
RUN rm -rf /opt/fixcheck \
 && chmod -R a+rwX /app /opt/cargo /opt/rustup /opt/golden

CMD ["/bin/bash"]