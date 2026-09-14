# ropewalk-passage: starship/starship issue #6861 - ANSI escape sequences are
# counted as printable columns by the grapheme width measurement used to lay
# out the `starship explain` breakdown table, so pre-colored module values
# misalign the columns.
#
# The image clones starship/starship SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree). The project's OWN regression
# test for the bug - the single inline `#[test]` function
# `test_grapheme_aware_width` as the FIX commit extends it (it gains the
# magenta-string assertion) - is extracted from the FIX commit at build time
# into /opt/golden/ (upstream test bytes never enter this repository). The
# fix commit is a descendant of the parent, so it is NOT reachable from the
# depth-1 clone the agent works on; the extraction uses a throwaway bare
# clone under /tmp that is deleted. Toolchain: rustup 1.98.1 pinned under
# /opt (the tree's edition-2024 sources need >= 1.85; Cargo.lock is
# committed, so --locked works). The heavy build (deps + binary + unit-test
# harness) is done once in this image so the trial's 1-vCPU work is a single
# incremental crate recompile only.
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT=109a6811cee1faae677a24a7d92fa8ed39397485
ARG UPSTREAM_SHA_FIX=2c11c086b8da5ea43ae795fa0e71a621e983ebcc

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

# Pin the rustup toolchain line exactly as the mining run did (1.98.1). The
# toolchain tree in /opt/rustup stays read-only for everyone, but cargo needs
# to create bookkeeping files inside CARGO_HOME and the trial may run as
# uid 1000, so the cargo home is world-writable (cheap: small files).
RUN curl -sSf https://sh.rustup.rs -o /tmp/rustup.sh \
 && sh /tmp/rustup.sh -y --default-toolchain none \
 && rustup toolchain install 1.98.1 \
 && rustup default 1.98.1 \
 && rustc --version && cargo --version \
 && rm -f /tmp/rustup.sh \
 && chmod -R a+rwX /opt/cargo

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/starship/starship.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Belt: prove the fix commit is not reachable from the trial clone and that
# the clone is exactly one commit.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test "$(git rev-list HEAD --count)" = "1"

# Extract the project's own regression test for the bug: the inline unit-test
# function `test_grapheme_aware_width` as the FIX commit extends it (the
# added "Magenta string test" assertion). The function already exists at the
# parent (without the magenta assertion); the whole fixed src/print.rs
# contains the FIX and must NOT be copied, so only the function body is
# extracted. Uses a THROWAWAY bare clone under /tmp that is deleted
# immediately afterwards: upstream test bytes never land in this task tree
# and the fix commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/starship/starship.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git show ${UPSTREAM_SHA_FIX}:src/print.rs > /tmp/print-fix.rs \
 && test -s /tmp/print-fix.rs \
 && grep -q "fn test_grapheme_aware_width(" /tmp/print-fix.rs

RUN mkdir -p /opt/golden \
 && python3 - /tmp/print-fix.rs /opt/golden/print_test.rs <<'PY'
import sys

src = open(sys.argv[1], encoding='utf-8').read()
marker = 'fn test_grapheme_aware_width('
fn_idx = src.index(marker)

# Back up over the attribute line(s) directly above the fn so the extracted
# chunk starts at the attribute line.
line_start = src.rfind('\n', 0, fn_idx) + 1
chunk_start = line_start
while True:
    prev_prev = src.rfind('\n', 0, line_start - 1)
    candidate = prev_prev + 1
    if src[candidate:line_start].strip().startswith('#['):
        chunk_start = candidate
        line_start = candidate
    else:
        break

# Copy the fn (string-literal aware) until its braces balance.
i = chunk_start
depth = 0
in_str = False
esc = False
while i < len(src):
    c = src[i]
    if in_str:
        if esc:
            esc = False
        elif c == '\\':
            esc = True
        elif c == '"':
            in_str = False
    else:
        if c == '"':
            in_str = True
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                i += 1
                break
    i += 1

out = src[chunk_start:i].rstrip() + '\n'
assert 'fn test_grapheme_aware_width(' in out
assert 'Magenta string test' in out
assert out.count('fn ') == 1
open(sys.argv[2], 'w', encoding='utf-8').write(out)
PY

RUN test -s /opt/golden/print_test.rs \
 && grep -q "fn test_grapheme_aware_width()" /opt/golden/print_test.rs \
 && grep -q "Magenta string test" /opt/golden/print_test.rs \
 && grep -q '\\x1B\[35;6mnormal text' /opt/golden/print_test.rs \
 && rm -rf /tmp/upstream-fix-clone /tmp/print-fix.rs

# The image is built as root; the trial may run as root or as uid 1000 (user
# `ubuntu` exists in the base image). Make the tree writable by uid 1000 and
# WARM every cache the trial needs AS that user, so every writable path
# (target/ under /app/src, cargo bookkeeping under /opt/cargo) is owned by
# uid 1000 from the start and /opt stays a read-only toolchain. The warm pass
# downloads all crates.io dependencies (Cargo.lock-pinned) and compiles the
# debug binary plus the unit-test harness, so the trial's 1-vCPU work is a
# one-crate incremental compile only.
WORKDIR /app
RUN chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/rustup && \
    cargo build --locked > /tmp/warm1.log 2>&1 && \
    cargo test --locked --no-run >> /tmp/warm1.log 2>&1'; rc=$?; \
    tail -5 /tmp/warm1.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    ls -la /app/src/target/debug/starship | awk '{print "binary:", $5, $9}'; \
    rm -f /tmp/warm1.log
# Second pass: must be fully up-to-date (proves the cache is complete for the
# offline trial, and that /opt/cargo is usable by uid 1000).
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/rustup && \
    cargo test --locked --no-run 2>&1 | tail -3'

# Harden against verifier-tampering: the cargo dispatcher (/opt/cargo/bin/cargo
# -> rustup), the rustup home and the golden regression test are owned by root
# and no longer world-writable. Cargo bookkeeping under /opt/cargo (not bin/)
# stays writable for warm-cache builds, and the pinning hashes in tests/test.sh
# back this up: a substituted dispatcher or a rewritten golden file cannot be
# produced by a non-root agent without failing the hash.
RUN chmod go-w /opt/cargo/bin /opt/cargo/bin/* \
 && chmod 755 /opt/rustup /opt/golden /opt/golden/print_test.rs \
 && chmod 444 /opt/golden/print_test.rs

# The trial has no network; make every cargo invocation fail closed on any
# network attempt instead of hanging on retries.
ENV CARGO_NET_OFFLINE=true

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]