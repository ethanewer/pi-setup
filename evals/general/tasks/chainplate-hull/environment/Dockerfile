ARG UPSTREAM_SHA_PARENT=0dd5a4f402c8d94524aaaa5632b2d0cba7fe1630
ARG UPSTREAM_SHA_FIX=91861886a779805cd8265a85c629e579d513aa75
ARG RUST_VERSION=1.98.1

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG RUST_VERSION

# The build chain is the "rustup" toolchain line 1.98.1, exactly as the
# mining run used. The repository's Cargo.lock pins every crate version, but
# the toolchain line is not pinned by Cargo.lock, so it is pinned explicitly
# here (the repo declares rust-version >= 1.90). The toolchain lives in /opt
# (read-only for everyone); only /app and the cargo target dir under
# /app/src are writable at trial time. The toolchain is installed with the
# minimal rustup profile (only rustc, cargo, rust-std): the task's build and
# test paths never invoke rustfmt, clippy or the rust-docs pages, so the
# default profile would only add dead weight. rustc/cargo are byte-identical
# to the default-profile install.
#
# Cargo needs to create bookkeeping files (package cache, sparse-index
# locks, downloaded crate archives) inside CARGO_HOME, and the trial may run
# as uid 1000; make the whole cargo home world-writable (matching the
# sibling v4.2 Rust tasks). The chmod lives in THIS RUN so the cargo home is
# stored once, with its final permissions, instead of being rewritten into a
# second layer.
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

RUN curl -sSf https://sh.rustup.rs -o /tmp/rustup.sh \
 && sh /tmp/rustup.sh -y --default-toolchain none \
 && rustup toolchain install ${RUST_VERSION} --profile minimal \
 && rustup default ${RUST_VERSION} \
 && chmod -R a+rwX /opt/cargo \
 && rustc --version && cargo --version \
 && rm -f /tmp/rustup.sh

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
#
# The image is built as root and the trial may run as root or as uid 1000
# (user `ubuntu` exists in the base image). The tree must be writable by
# uid 1000, so the ownership change is folded into this same RUN: the source
# tree is then stored in exactly one layer, with its final (a+rwX,
# 1000:1000) modes, rather than being rewritten into a second layer by a
# later RUN. git config is written to /etc/gitconfig (outside /app/src), so
# it is not affected by this.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/starship/starship.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && { chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true; }

# Extract the project's own regression tests for this bug (the three inline
# `mod tests` functions that the fix commit adds to
# src/formatter/string_formatter.rs) into /opt/golden using a THROWAWAY clone
# that is deleted immediately afterwards, so upstream test bytes never land
# in this task tree and the fix commit never lands in /app/src. The extracted
# block is the whole `mod tests { .. }` module exactly as the fix commit
# ships it: it compiles against the parent tree (the three added functions
# use only pre-existing APIs) and only their runtime assertions fail there.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/starship/starship.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git checkout -q --detach FETCH_HEAD \
 && mkdir -p /opt/golden \
 && test -s src/formatter/string_formatter.rs \
 && python3 - <<'PY'
path = "/tmp/upstream-fix-clone/src/formatter/string_formatter.rs"
lines = open(path).read().splitlines()
start = next(i for i, l in enumerate(lines) if l.strip() == "mod tests {")
end = len(lines) - 1
assert lines[end].strip() == "}", "tests module does not close the file"
block = "\n".join(lines[start:end + 1]) + "\n"
for name in ("test_empty_textgroup_with_style",
             "test_empty_textgroup_without_style",
             "test_empty_textgroup_propagates_prev_bg"):
    assert name in block, "golden block missing " + name
open("/opt/golden/string_formatter_tests.rs", "w").write(block)
import shutil
shutil.rmtree("/tmp/upstream-fix-clone")
print("extracted %d lines to /opt/golden/string_formatter_tests.rs" % len(block.splitlines()))
PY

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && (graded_tree="$(git count-objects -v | sed -n 's/^count: //p')"; \
     echo "object count in /app/src: $graded_tree")

# WARM every cache the trial needs AS uid 1000 (user `ubuntu` in the base
# image), so every writable path (target/, cargo bookkeeping) is owned by
# uid 1000 from the start and /opt stays a read-only toolchain (the clone
# RUN above already made /app/src writable by uid 1000). The warm pass
# downloads all crates.io dependencies (Cargo.lock-pinned) and compiles the
# whole workspace plus the `starship` binary and the test harness; the trial
# has no network, so this layer IS the warm cache. The build logs are
# removed in the same RUN that created them, so they never enter the image.
WORKDIR /app
RUN test -s /opt/golden/string_formatter_tests.rs && echo "golden tests block present"
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo build --locked > /tmp/warm1.log 2>&1'; rc=$?; \
    tail -5 /tmp/warm1.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    test -x /app/src/target/debug/starship && echo "starship debug binary built" || { echo "no starship binary"; exit 1; }; \
    rm -f /tmp/warm1.log
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --no-run --locked > /tmp/warm2.log 2>&1'; rc=$?; \
    tail -8 /tmp/warm2.log; \
    if [ $rc -ne 0 ]; then echo "WARM TEST-BUILD FAILED (exit $rc)"; exit $rc; fi; \
    echo "test harness compiled"; \
    rm -f /tmp/warm2.log

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]