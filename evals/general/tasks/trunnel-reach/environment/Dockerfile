FROM bench-base:python-3.12
ARG UPSTREAM_SHA=f4ea23575ecb4802ede51401bb297d1cb3c1610e
WORKDIR /app

# toolchain needed to build angr's own wheel (native C++ unicornlib + Rust ext)
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gcc g++ make curl \
 && rm -rf /var/lib/apt/lists/*
# angr's native component pins rust-toolchain channel 1.96 (Debian rustc 1.85 is too old for pyo3)
RUN curl -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh \
 && sh /tmp/rustup-init.sh -y --default-toolchain 1.96 --profile minimal \
 && rm -f /tmp/rustup-init.sh
ENV PATH="/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
# pin and clone the upstream repository shallow; fail closed if the commit moves
RUN git clone --depth 1 --branch v9.3.4 https://github.com/angr/angr.git /app/src/angr \
 && cd /app/src/angr \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"
# build and install the pinned upstream library from source; warm the import
RUN pip install --no-cache-dir /app/src/angr \
 && python3 -c "import angr, claripy" \
 && rm -rf /root/.cargo /root/.rustup

# ---- authored fixture: the visible crackme (binary only; source never shipped) ----
RUN cat > /tmp/crackme.c <<'CEOF'
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>

static uint32_t rotl(uint32_t v, int n) { return (v << n) | (v >> (32 - n)); }

static const uint32_t KEYS[16] = {
    0xc735df5eu, 0x70d3da1fu, 0x1de9ea66u, 0x01eaf614u,
    0x17346b45u, 0xe935b870u, 0xf149f542u, 0xf073eed1u,
    0xce97b5bdu, 0x950cddd9u, 0x08f0ebd4u, 0xabeb9592u,
    0xb16e2d5cu, 0x157cf9c6u, 0x19322fedu, 0xc4381836u,
};

int main(void) {
    unsigned char buf[16];
    ssize_t n = read(0, buf, 16);
    if (n != 16) { puts("ACCESS DENIED"); return 1; }
    for (int i = 0; i < 16; i++) {
        if (buf[i] < 0x20 || buf[i] > 0x7e) { puts("ACCESS DENIED"); return 1; }
    }
    uint32_t acc = 0x811c9dc5u ^ 0xf7697fb9u;
    for (int i = 0; i < 16; i++) {
        uint32_t x = buf[i];
        x ^= (x << 4) & 0xff;
        x ^= x >> 3;
        x = rotl(x, 2) & 0xff;
        x ^= (x << 1) & 0xff;
        x ^= x >> 5;
        acc = (acc ^ (rotl(acc, 7) ^ 0x9e3779b9u));
        acc += x;
        acc ^= KEYS[i];
    }
    if (acc == 0x57b1fb97u) { puts("ACCESS GRANTED"); return 0; }
    puts("ACCESS DENIED");
    return 1;
}
CEOF
RUN mkdir -p /app/challenge \
 && gcc -O1 -o /app/challenge/crackme /tmp/crackme.c \
 && rm -f /tmp/crackme.c \
 && printf 'ReachMeabcdefghi' | /app/challenge/crackme | grep -q 'ACCESS GRANTED' \
 && chmod -R a+rwX /app /app/challenge

COPY files/ /app/