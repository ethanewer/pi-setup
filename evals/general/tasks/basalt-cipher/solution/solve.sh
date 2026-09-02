#!/usr/bin/env bash
# Oracle: build the basalt cipher project from scratch and expose it.
set -euo pipefail
cd /app

# ---------------------------------------------------------------- sources
mkdir -p src bin
cat > src/prog.c <<'EOF'
/* basalt prog — fixed-argument-order block cipher CLI. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int hexv(char c){
    if (c>='0'&&c<='9') return c-'0';
    if (c>='a'&&c<='f') return c-'a'+10;
    if (c>='A'&&c<='F') return c-'A'+10;
    return -1;
}

static unsigned char *hexdec(const char *s, size_t *len){
    size_t L = strlen(s);
    if (L % 2 != 0) return NULL;
    size_t n = L/2;
    unsigned char *b = malloc(n ? n : 1);
    if (!b) return NULL;
    for (size_t i=0;i<n;i++){
        int hi = hexv(s[2*i]);
        int lo = hexv(s[2*i+1]);
        if (hi<0 || lo<0){ free(b); return NULL; }
        b[i] = (unsigned char)((hi<<4)|lo);
    }
    *len = n;
    return b;
}

static void usage(FILE *f){
    fprintf(f, "usage: prog [xor|skip] HEXKEY HEXDATA\n");
}

int main(int argc, char **argv){
    if (argc != 4){
        usage(stderr); return 1;
    }
    const char *mode = argv[1];
    if (strcmp(mode,"xor")!=0 && strcmp(mode,"skip")!=0){
        usage(stderr); return 1;
    }
    size_t kl, dl;
    unsigned char *k = hexdec(argv[2], &kl);
    if (!k){ fprintf(stderr,"prog: invalid hex key\n"); return 2; }
    unsigned char *d = hexdec(argv[3], &dl);
    if (!d){ free(k); fprintf(stderr,"prog: invalid hex data\n"); return 2; }
    if (kl == 0){
        free(k); free(d);
        fprintf(stderr,"prog: empty key\n");
        return 2;
    }
    if (dl == 0){
        free(k); free(d);
        printf("\n");
        return 0;
    }
    size_t m = kl, n = dl;
    unsigned char *out = malloc(n);
    if (!out){ free(k); free(d); return 2; }
    if (strcmp(mode,"xor")==0){
        for (size_t i=0;i<n;i++)
            out[i] = (unsigned char)(d[i] ^ k[i % m]);
    } else {
        for (size_t i=0;i<n;i++)
            out[i] = (unsigned char)((d[i] + (unsigned int)k[(i*3)%m] * (unsigned int)((i%8)+1)) & 0xFF);
    }
    for (size_t i=0;i<n;i++)
        printf("%02x", out[i]);
    printf("\n");
    free(k); free(d); free(out);
    return 0;
}
EOF

cat > src/weft.c <<'EOF'
/* weft — decimal byte-length reporter (third executable). */
#include <stdio.h>
#include <string.h>

static int hexv(char c){
    if (c>='0'&&c<='9') return c-'0';
    if (c>='a'&&c<='f') return c-'a'+10;
    if (c>='A'&&c<='F') return c-'A'+10;
    return -1;
}

int main(int argc, char **argv){
    if (argc != 2){
        fprintf(stderr, "usage: weft <hex>\n");
        return 1;
    }
    const char *s = argv[1];
    size_t L = strlen(s);
    if (L % 2 != 0) return 2;
    size_t n = 0;
    for (size_t i=0;i<L;i+=2)
        if (hexv(s[i])<0 || hexv(s[i+1])<0) return 2;
        else n++;
    printf("weft=%zu\n", n);
    return 0;
}
EOF

cat > src/selftest.c <<'EOF'
/* selftest — untouched smoke-test, returns a success sentinel. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char keyv[3] = {0x3c, 0x5f, 0x9a};

static void enc_xor(const unsigned char *d, size_t n, unsigned char *o){
    for (size_t i=0;i<n;i++)
        o[i] = (unsigned char)(d[i] ^ keyv[i % 3]);
}

int main(void){
    int rc = 1;
    const unsigned char msg[] = { 'b','a','s','a','l','t','-','c','i','p' };
    size_t n = sizeof msg;
    unsigned char *c = malloc(n), *p = malloc(n);
    if (!c || !p){ fprintf(stderr,"SELFTEST_FAIL\n"); return 1; }

    enc_xor(msg, n, c);
    enc_xor(c, n, p);           /* self-inverse round-trip */

    int ok = (memcmp(p, msg, n)==0);
    if (!ok){ fprintf(stderr,"SELFTEST_FAIL\n"); goto done; }

    unsigned char a = (unsigned char)(0xbe ^ 0x0a);
    ok = ok && (a == 0xb4);
    unsigned char s = (unsigned char)((0x02 + 0x01) & 0xFF);
    ok = ok && (s == 0x03);

    if (ok){
        printf("SELFTEST_OK\n");
        rc = 0;
    } else {
        fprintf(stderr, "SELFTEST_FAIL\n");
    }
done:
    free(c); free(p);
    return rc;
}
EOF

cat > CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(basalt LANGUAGES C)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin)

set(STATIC_FLAGS "-static")
add_executable(prog src/prog.c)
target_link_libraries(prog PRIVATE ${STATIC_FLAGS})
add_executable(weft src/weft.c)
target_link_libraries(weft PRIVATE ${STATIC_FLAGS})
add_executable(selftest src/selftest.c)
target_link_libraries(selftest PRIVATE ${STATIC_FLAGS})
EOF

cat > /app/Makefile <<'EOF'
.PHONY: all clean
all:
	cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
	cmake --build build -j2
clean:
	rm -rf build bin
EOF

cat > /app/build.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
make >/dev/null
DIST="dist"
STAGE="$DIST/release"
PKG="basalt-1.2"
rm -rf "$DIST"
mkdir -p "$STAGE/$PKG/src"
cp CMakeLists.txt Makefile build.sh "$STAGE/$PKG/"
cp src/*.c "$STAGE/$PKG/src/"
tar --format=gnu --sort=name --owner=0 --group=0 --numeric-owner \
    --mtime=@0 --no-acls --no-xattrs -C "$STAGE" -cf - "$PKG" \
  | zstd -19 -q -f -o "$DIST/basalt-src.tar.zst"
rm -rf "$STAGE"
echo "wrote $DIST/basalt-src.tar.zst"
EOF
chmod +x /app/build.sh

# ---------------------------------------------------------------- build
make >/dev/null

# ------------------------------------------------- PATH exposure (bare use)
ln -sf /app/bin/prog /usr/local/bin/prog
ln -sf /app/bin/selftest /usr/local/bin/selftest

# --------------------------------------------------------- release archive
./build.sh
echo "ORACLE_DONE"