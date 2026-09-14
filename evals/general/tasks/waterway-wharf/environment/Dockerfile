ARG UPSTREAM_SHA_PARENT=c5e9de9d6e07786eb1ff7f88d7871e0f0ef28c32
ARG UPSTREAM_SHA_FIX=f15f3dcbc340eb98b40e60cc8b797263963d1e97

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Toolchain: the rustup stable line 1.98.1, the same version the mining run
# used (Ubuntu 24.04's apt rustc 1.75 is too old for the resolved crates.io
# graph). Lives in /opt: the toolchain tree (/opt/rustup) is read-only for
# everyone; cargo's own bookkeeping (/opt/cargo) is world-writable because the
# trial may run as uid 1000.
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential curl ca-certificates git pkg-config libssl-dev \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

RUN curl -sSf https://sh.rustup.rs -o /tmp/rustup.sh \
 && sh /tmp/rustup.sh -y --default-toolchain none \
 && rustup toolchain install 1.98.1 \
 && rustup default 1.98.1 \
 && rustc --version && cargo --version \
 && rm -f /tmp/rustup.sh \
 && chmod -R a+rwX /opt/cargo

# Clone the REAL upstream repository (rust-lang/regex) at exactly the parent
# commit, with the shallowest possible history: `git init` + one depth-1 fetch
# of the pinned SHA. The object store in /app/src holds ONLY the parent
# commit. The fix commit is never fetched into this clone; reachability is
# asserted below, so the build fails closed if upstream ever moves.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/rust-lang/regex.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# Extract the project's own regression test for this bug (the entry the fix
# commit adds to testdata/regression.toml) into /opt/golden using a THROWAWAY
# clone that is deleted immediately afterwards, so the fix commit never lands
# in /app/src and no upstream test bytes enter this task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/rust-lang/regex.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:testdata/regression.toml \
      > /opt/golden/regression.toml \
 && test -s /opt/golden/regression.toml \
 && grep -q 'name = "non-prefix-literal-quit-state"' /opt/golden/regression.toml \
 && grep -Fq 'haystack = "β77\n"' /opt/golden/regression.toml \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt 1: the fix commit must be unreachable from the trial clone.
# Belt 2: the golden bytes and the toolchain are sha256-pinned so the verifier
# detects substitution of either.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/regression.toml > /opt/pins/golden.sha256 \
 && sha256sum /opt/cargo/bin/rustc /opt/cargo/bin/cargo /opt/cargo/bin/rustup \
                 /opt/rustup/toolchains/1.98.1-x86_64-unknown-linux-gnu/bin/rustc \
                 /usr/bin/git /usr/bin/bash > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins /opt/golden \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/regression.toml \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + toolchain pinned"

# WARM BUILD, as uid 1000 (user `ubuntu` exists in the base image): resolves
# the full crates.io graph (no committed Cargo.lock, so this pass writes one
# pinned to today's crates.io state), compiles the workspace and the
# repository's own `integration` test target (tests/lib.rs), and runs the whole
# existing suite once at the parent commit: it must be green. The trial has no
# network, so this layer IS the warm cache; the agent's rebuilds after editing
# a source file are incremental and take seconds.
WORKDIR /app
RUN chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --no-run --test integration -j1 > /tmp/warm-build.log 2>&1' ; rc=$?; \
    tail -3 /tmp/warm-build.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit 1; fi; \
    rm -f /tmp/warm-build.log
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --test integration -j1 > /tmp/warm-test.log 2>&1'; rc=$?; \
    tail -3 /tmp/warm-test.log; \
    if [ $rc -ne 0 ]; then echo "WARM TEST RUN FAILED (exit $rc)"; exit 1; fi; \
    grep -q "test result: ok" /tmp/warm-test.log || { echo "suite not fully green at parent"; exit 1; }; \
    rm -f /tmp/warm-test.log

# PARENT-DIRECTION confirmation IN THIS IMAGE (as uid 1000): plant the golden
# entry, rebuild, run the harness filtered to it: the harness must FAIL with
# the truncated match (bytes 3..5 instead of 0..5), then restore the pristine
# data file. Fails closed if the pinned dependency set no longer reproduces
# the bug.
RUN cat > /tmp/parentcheck.sh <<'SH'
#!/bin/bash
set -u
export PATH="/opt/cargo/bin:$PATH" CARGO_NETWORK_OFFLINE=true
export RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo
cd /app/src || exit 1
cat >> testdata/regression.toml <<'EOF'

[[test]]
name = "non-prefix-literal-quit-state"
regex = '.+\b\n'
haystack = "β77\n"
matches = [[0, 5]]
EOF
touch testdata/regression.toml
sleep 1
REGEX_TEST=regression/non-prefix-literal-quit-state cargo test --test integration -j1 \
    > /tmp/parentcheck.out 2>&1
rc=$?
tail -8 /tmp/parentcheck.out
[ $rc -ne 0 ] || { echo "PARENT-DIRECTION: golden case unexpectedly PASSED"; exit 1; }
grep -q "did not find expected matches" /tmp/parentcheck.out \
    || { echo "PARENT-DIRECTION: missing harness failure text"; exit 1; }
grep -q "Match(0: 3..5)" /tmp/parentcheck.out \
    || { echo "PARENT-DIRECTION: truncated match span is not 3..5"; exit 1; }
git checkout -q HEAD -- testdata/regression.toml || exit 1
git status --porcelain | grep -q . && { echo "PARENT-DIRECTION: tree dirty after restore"; exit 1; }
echo "PARENT-DIRECTION OK: bug reproduces in this exact image (3..5, not 0..5)"
SH
RUN chmod 755 /tmp/parentcheck.sh \
 && su -s /bin/bash ubuntu -c '/tmp/parentcheck.sh' \
 && rm -f /tmp/parentcheck.sh

# FIX-DIRECTION confirmation IN THIS IMAGE: clone the working tree to a
# throwaway copy, apply the upstream fix (embedded transiently here; the file
# is deleted in this same RUN so no fix bytes survive in the image), plant the
# golden entry, rebuild from scratch, and require the same harness invocation
# to PASS with the full match. Both directions are thus re-confirmed inside
# this exact image before the task ships.
RUN cat > /tmp/fixcheck.patch <<'PATCH'
diff --git a/regex-automata/src/meta/limited.rs b/regex-automata/src/meta/limited.rs
--- a/regex-automata/src/meta/limited.rs
+++ b/regex-automata/src/meta/limited.rs
@@ -69,9 +69,6 @@ pub(crate) fn dfa_try_search_half_rev(
             } else if dfa.is_dead_state(sid) {
                 return Ok(mat);
             } else if dfa.is_quit_state(sid) {
-                if mat.is_some() {
-                    return Ok(mat);
-                }
                 return Err(MatchError::quit(input.haystack()[at], at).into());
             }
         }
@@ -155,9 +152,6 @@ pub(crate) fn hybrid_try_search_half_rev(
             } else if sid.is_dead() {
                 return Ok(mat);
             } else if sid.is_quit() {
-                if mat.is_some() {
-                    return Ok(mat);
-                }
                 return Err(MatchError::quit(input.haystack()[at], at).into());
             }
         }
@@ -209,9 +203,6 @@ fn dfa_eoi_rev(
             let pattern = dfa.match_pattern(*sid, 0);
             *mat = Some(HalfMatch::new(pattern, sp.start));
         } else if dfa.is_quit_state(*sid) {
-            if mat.is_some() {
-                return Ok(());
-            }
             return Err(MatchError::quit(byte, sp.start - 1));
         }
     } else {
@@ -246,9 +237,6 @@ fn hybrid_eoi_rev(
             let pattern = dfa.match_pattern(cache, *sid, 0);
             *mat = Some(HalfMatch::new(pattern, sp.start));
         } else if sid.is_quit() {
-            if mat.is_some() {
-                return Ok(());
-            }
             return Err(MatchError::quit(byte, sp.start - 1));
         }
     } else {
diff --git a/regex-automata/src/meta/stopat.rs b/regex-automata/src/meta/stopat.rs
--- a/regex-automata/src/meta/stopat.rs
+++ b/regex-automata/src/meta/stopat.rs
@@ -81,9 +81,6 @@ pub(crate) fn dfa_try_search_half_fwd(
             } else if dfa.is_dead_state(sid) {
                 return Ok(mat.ok_or(at));
             } else if dfa.is_quit_state(sid) {
-                if mat.is_some() {
-                    return Ok(mat.ok_or(at));
-                }
                 return Err(MatchError::quit(input.haystack()[at], at).into());
             } else {
                 // Ideally we wouldn't use a DFA that specialized start states
@@ -122,9 +119,6 @@ pub(crate) fn hybrid_try_search_half_fwd(
             } else if sid.is_dead() {
                 return Ok(mat.ok_or(at));
             } else if sid.is_quit() {
-                if mat.is_some() {
-                    return Ok(mat.ok_or(at));
-                }
                 return Err(MatchError::quit(input.haystack()[at], at).into());
             } else {
                 // We should NEVER get an unknown state ID back from
@@ -162,9 +156,6 @@ fn dfa_eoi_fwd(
                 let pattern = dfa.match_pattern(*sid, 0);
                 *mat = Some(HalfMatch::new(pattern, sp.end));
             } else if dfa.is_quit_state(*sid) {
-                if mat.is_some() {
-                    return Ok(());
-                }
                 return Err(MatchError::quit(b, sp.end));
             }
         }
@@ -201,9 +192,6 @@ fn hybrid_eoi_fwd(
                 let pattern = dfa.match_pattern(cache, *sid, 0);
                 *mat = Some(HalfMatch::new(pattern, sp.end));
             } else if sid.is_quit() {
-                if mat.is_some() {
-                    return Ok(());
-                }
                 return Err(MatchError::quit(b, sp.end));
             }
         }
PATCH
RUN cat > /tmp/fixcheck.sh <<'SH'
#!/bin/bash
set -u
export PATH="/opt/cargo/bin:$PATH" CARGO_NETWORK_OFFLINE=true
export RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo
rm -rf /tmp/fixcheck && mkdir -p /tmp/fixcheck && cd /tmp/fixcheck || exit 1
git init -q && git remote add local /app/src \
 && git fetch -q --depth 1 local HEAD \
 && git checkout -q --detach FETCH_HEAD || exit 1
git apply /tmp/fixcheck.patch || { echo "fixcheck: patch did not apply"; exit 1; }
cp /opt/golden/regression.toml testdata/regression.toml
touch testdata/regression.toml regex-automata/src/meta/limited.rs regex-automata/src/meta/stopat.rs
sleep 1
REGEX_TEST=regression/non-prefix-literal-quit-state cargo test --test integration -j1 \
    > /tmp/fixcheck.out 2>&1
rc=$?
tail -5 /tmp/fixcheck.out
[ $rc -eq 0 ] || { echo "FIX-DIRECTION: golden case did not pass after the fix"; exit 1; }
grep -q "test result: ok" /tmp/fixcheck.out || { echo "FIX-DIRECTION: not ok"; exit 1; }
echo "FIX-DIRECTION OK: golden case passes after the fix"
SH
RUN chmod 755 /tmp/fixcheck.sh \
 && bash /tmp/fixcheck.sh \
 && rm -rf /tmp/fixcheck /tmp/fixcheck.patch /tmp/fixcheck.sh /tmp/fixcheck.out

COPY files/ /app/
RUN chmod a+rwX /app

# The trial has no network: cargo must not attempt any, ever. The dependency
# cache and Cargo.lock are warm; only an index refresh would have needed the
# network.
ENV CARGO_NETWORK_OFFLINE=true

CMD ["/bin/bash"]