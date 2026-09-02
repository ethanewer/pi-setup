#!/usr/bin/env bash
#
# Oracle solution for drift-wharf.
# Real work: build the Zephyr compiler from source, compile the bundled decoder
# with it, author and compile a byte-exact general drift encoder, produce the
# round-trip deliverables, and gate cardinal.h behind strict C++11.
set -euo pipefail

echo "[solve] build Zephyr compiler from its source tree"
cd /app/src/zephyr
make all >/dev/null
make install >/dev/null
# Sanity: the built compiler really compiles and runs a new program.
printf 'int main(){ out(65); return 0; }\n' > /tmp/zsmoke.zh
/app/cc/bin/cc -o /tmp/zsmoke /tmp/zsmoke.zh
[ "$(/tmp/zsmoke)" = "A" ] || { echo "[solve] compiler smoke failed"; exit 1; }

echo "[solve] compile the bundled drift decoder with the built compiler"
/app/cc/bin/cc -o /app/unpack /app/deck/drift.zh

echo "[solve] author the general drift encoder (Zephyr)"
cat > /app/pack.zh <<'ZH_EOF'
/* pack.zh - Zephyr drift stream encoder.
 * Reads any payload on stdin, writes a drift stream that the bundled decoder
 * reproduces byte-for-byte. Long equal runs use RLE frames (split >128);
 * length-1 runs coalesce into literals of up to 128 bytes. */
byte ZBUF[200000];

int runlen(int i, int len){
    int v = ZBUF[i];
    int k = i;
    while (k < len){
        if (ZBUF[k] != v) return k - i;
        k = k + 1;
    }
    return k - i;
}

int main(){
    int len = read_all(ZBUF);
    if (len < 0){ len = 0; }
    int i = 0;
    while (i < len){
        int rl = runlen(i, len);
        if (rl >= 2){
            int t = rl;
            while (t > 0){
                int c = t; if (c > 128){ c = 128; }
                out(0x80 + (c - 1));
                out(ZBUF[i]);
                t = t - c;
            }
            i = i + rl;
        } else {
            int start = i; int n = 0;
            while (i < len){
                if ((i - start) >= 128) break;
                if (runlen(i, len) >= 2) break;
                i = i + 1; n = n + 1;
            }
            out(n - 1);
            int j = start;
            while (j < start + n){ out(ZBUF[j]); j = j + 1; }
        }
    }
    return 0;
}
ZH_EOF
/app/cc/bin/cc -o /app/pack /app/pack.zh

echo "[solve] end-to-end round trip over the visible corpus"
/app/pack    < /app/data/reference.txt > /app/drifted.bin
/app/unpack  < /app/drifted.bin         > /app/recovered.bin
cmp /app/recovered.bin /app/data/reference.txt
sha=$(sha256sum /app/recovered.bin | awk '{print $1}')
printf 'ROUNDTRIP_OK %s\n' "$sha" > /app/verify.txt

echo "[solve] strict C++11 probe on cardinal.h"
g++ -std=c++11 -pedantic-errors -I/app/deck -c /app/probe/probe.cpp -o /app/probe.o

echo "[solve] deliverables:"
ls -l /app/cc/bin/cc /app/unpack /app/pack /app/drifted.bin /app/recovered.bin /app/probe.o /app/verify.txt
echo "[solve] done"