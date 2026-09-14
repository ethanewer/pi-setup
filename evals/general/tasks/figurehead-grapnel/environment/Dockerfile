# figurehead-grapnel: curl upstream-clone task (IMAP mailbox-case bug, issue #22868)
# Shipped repo: curl/curl at parent commit 81787b0b34c496c46870751f6ca438346036d7a0
# (fix 12cfc836c6fe8f4e4e5001f400d677f0aa530421 is intentionally NOT reachable here).
FROM bench-base:ubuntu-24.04

# --- toolchain and test dependencies (recipe from the mined entry) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool pkg-config perl \
        openssl libssl-dev zlib1g-dev libpsl-dev libzstd-dev libbrotli-dev \
        strace patch git ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*

# --- upstream pins, resolved from https://github.com/curl/curl ---
ARG UPSTREAM_SHA=81787b0b34c496c46870751f6ca438346036d7a0
ARG FIX_SHA=12cfc836c6fe8f4e4e5001f400d677f0aa530421

ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

WORKDIR /app

# --- shipped repository: upstream curl, shallow clone, detached at the PARENT commit.
#     Fails closed if upstream moved; asserts the FIX commit object is NOT reachable
#     in the shipped clone. ---
RUN git clone --depth 1 https://github.com/curl/curl.git /app/curl \
 && cd /app/curl \
 && git fetch --depth 1 origin "$UPSTREAM_SHA" \
 && git checkout -q "$UPSTREAM_SHA" \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "$FIX_SHA^{commit}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build the project once. One CPU, static binary: the copied pre-fix binary must
#     stay self-contained so later relinks of libcurl cannot change its behaviour. ---
RUN cd /app/curl && autoreconf -fi \
 && ./configure --with-openssl --enable-debug --disable-shared --enable-static >/dev/null \
 && make -j1 >/dev/null
RUN cd /app/curl/tests && make all >/dev/null \
 && cp /app/curl/src/curl /opt/curl.buggy \
 && /opt/curl.buggy --version | head -1 \
 && chown -R 1000:1000 /app/curl

# --- golden regression test (tests/data/test804 at the FIX commit) extracted via a
#     throwaway clone under /tmp; the clone is deleted so the fix object never ships.
#     /opt/golden-test804 is the verifier's canonical copy. ---
RUN git init -q /tmp/golden-clone \
 && cd /tmp/golden-clone \
 && git remote add origin https://github.com/curl/curl.git \
 && git fetch --depth 1 origin "$FIX_SHA" \
 && git show "$FIX_SHA:tests/data/test804" > /opt/golden-test804 \
 && cd / \
 && rm -rf /tmp/golden-clone \
 && test ! -d /tmp/golden-clone \
 && test -s /opt/golden-test804 \
 && grep -q "IMAP selects a mailbox when its case changes" /opt/golden-test804

# --- the agent and the verifier run as uid 1000: the tree was chown'd in the
#     same RUN that built it (one layer, no copy-on-write duplication). ---
COPY files/ /app/