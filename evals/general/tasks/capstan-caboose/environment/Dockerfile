# capstan-caboose: starship/starship issue #7426 - the maven module falsely
# activates in any directory that merely contains an .mvn folder.
#
# The image clones starship/starship SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree) and extracts the project's own
# regression test for the bug (the single test function the FIX commit adds
# inside `mod tests` of src/modules/maven.rs) from the FIX commit at build
# time into /opt/golden/ (upstream bytes never enter this repository). The
# fix commit is a descendant of the parent, so it is NOT reachable from the
# depth-1 clone the agent works on; the extraction uses a throwaway bare
# clone that is deleted. Toolchain: rustup 1.98.1 pinned under /opt (edition
# 2024 needs >= 1.85; the tree's Cargo.lock is committed, so --locked works).
# The heavy build (deps + binary + test harness) is done once in this image so
# the trial's 1-vCPU work is incremental only.
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT=d0e246802c85d5aa956f536f9ab7ead282dbab7a
ARG UPSTREAM_SHA_FIX=d455255e7bc5ae5e96ac5a3e2610458a9f213b49

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

# Pin the rustup toolchain line exactly as the mining run did; the toolchain
# tree in /opt/rustup stays read-only for everyone, but cargo needs to create
# bookkeeping files inside CARGO_HOME and the trial may run as uid 1000, so
# the whole cargo home is world-writable (cheap: a few thousand small files).
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

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test "$(git rev-list HEAD --count)" = "1"

# Extract the project's own regression test for the bug: the single function
# `folder_with_maven_config_does_not_trigger_module` that the FIX commit adds
# inside `mod tests` of src/modules/maven.rs (starship keeps unit tests inline
# in the source, so there is no separate test file to extract; the rest of the
# fixed file contains the fix and must NOT be copied). Uses a THROWAWAY bare
# clone that is deleted immediately afterwards, so upstream test bytes never
# land in this task tree and the fix commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/starship/starship.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git show ${UPSTREAM_SHA_FIX}:src/modules/maven.rs > /tmp/maven-fix.rs \
 && test -s /tmp/maven-fix.rs \
 && grep -q "fn folder_with_maven_config_does_not_trigger_module(" /tmp/maven-fix.rs

RUN mkdir -p /opt/golden \
 && python3 - /tmp/maven-fix.rs /opt/golden/maven_test.rs <<'PY'
import sys

src = open(sys.argv[1], encoding='utf-8').read()
marker = 'fn folder_with_maven_config_does_not_trigger_module('
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
assert 'fn folder_with_maven_config_does_not_trigger_module(' in out
assert out.count('fn ') == 1
open(sys.argv[2], 'w', encoding='utf-8').write(out)
PY

RUN test -s /opt/golden/maven_test.rs \
 && grep -q "fn folder_with_maven_config_does_not_trigger_module() -> io::Result<()>" /opt/golden/maven_test.rs \
 && grep -q 'maven.config' /opt/golden/maven_test.rs \
 && rm -rf /tmp/upstream-fix-clone /tmp/maven-fix.rs

# The image is built as root; the trial may run as root or as uid 1000
# (user `ubuntu` exists in the base image). Make the tree writable by
# uid 1000 and WARM every cache the trial needs AS that user, so every
# writable path (target/ under /app/src, cargo bookkeeping under /opt/cargo)
# is owned by uid 1000 from the start and /opt stays a read-only toolchain.
# The warm pass downloads all crates.io dependencies (Cargo.lock-pinned) and
# compiles the debug binary plus the test harness, so the trial's 1-vCPU work
# is a one-crate incremental compile only.
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
# offline trial, and that /opt/cargo is usable by uid 1000 read-only).
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/rustup && \
    cargo test --locked --no-run 2>&1 | tail -3'

# Harden against verifier-tampering: the cargo dispatcher (/opt/cargo/bin/cargo
# -> rustup), the rustup home and the golden regression test are owned by root
# and no longer world-writable. Cargo bookkeeping under /opt/cargo (not bin/)
# stays writable for warm-cache builds, and the pinning hashes in tests/test.sh
# back this up: a substituted or re-pointed dispatcher or a rewritten golden
# file can no longer be produced by a non-root agent without failing the hash.
# The warm builds above ran as uid 1000 and preceded this step, so the image
# still ships every cache warm and owned by 1000 where the trial writes.
RUN chmod go-w /opt/cargo/bin /opt/cargo/bin/* \
 && chmod 755 /opt/rustup /opt/golden /opt/golden/maven_test.rs \
 && chmod 444 /opt/golden/maven_test.rs

# The trial has no network; make every cargo invocation fail closed on any
# network attempt instead of hanging on retries.
ENV CARGO_NET_OFFLINE=true

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]