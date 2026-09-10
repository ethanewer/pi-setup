#!/usr/bin/env bash
# Verifier for kedge-lattice (real libvips 8.18.6 built from a clean
# checkout at trial time).
#
# What is measured:
#  1. /app/vips is a real install produced by the agent: an ELF vips binary
#     reporting 8.18.6, libvips.so.42 with SONAME libvips.so.42, headers and
#     a working vips.pc.
#  2. The agent's deliverable /app/out files are recomputed by the verifier
#     with the agent's own installed vips binary using the documented
#     pipeline (rotate 90 clockwide, top-left half crop, 0.5 nearest-
#     neighbour rescale); the recomputed pixels must be bit-identical to the
#     agent's files, and width/height/bands must be right.
#  3. The same three operations are run with the agent's binary on three
#     hidden images; md5-of-raw-pixels and header metadata must match
#     reference values computed from an independent reference build of the
#     same pinned commit (the operations are bit-exact by construction:
#     rotate is a pixel permutation, extract_area an integer crop, resize
#     with --kernel nearest integer sampling).
#  4. A hidden C program is compiled against the agent-installed library
#     (gcc + pkg-config) and reproduces the same pipeline via the vips C
#     API; its FNV checksum over the raw pixels must match the reference.
# A nop container scores 0: nothing was built, so /app/vips does not exist,
# /app/out is absent, and no hidden operation can even run.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

FAILS=0
TMP=$(mktemp -d)

V=/app/vips/bin/vips
H=/app/vips/bin/vipsheader

fail() { echo "FAIL: $1" >&2; FAILS=1; }

# ---------------------------------------------------------------------------
# 1. the install under /app/vips exists and is a real build of the pinned
#    version (an ELF binary, the right SONAME, headers, a .pc file).
# ---------------------------------------------------------------------------
LIB=$(find /app/vips/lib -name 'libvips.so.42' 2>/dev/null | head -n1)
PC=$(find /app/vips/lib -name 'vips.pc' 2>/dev/null | head -n1)
if [ -z "$LIB" ]; then
    fail "libvips.so.42 not found under /app/vips/lib"
else
    if ! readelf -d "$LIB" 2>/dev/null | grep -q "SONAME.*libvips.so.42"; then
        fail "installed library does not declare SONAME libvips.so.42"
    fi
fi
if [ -z "$PC" ]; then
    fail "vips.pc not found under /app/vips/lib"
fi
if [ ! -f /app/vips/include/vips/vips.h ]; then
    fail "C headers not installed at /app/vips/include/vips/vips.h"
fi

# The installed tools and the hidden C program must run against the agent's
# own library and pkg-config metadata, wherever meson placed them.
export LD_LIBRARY_PATH="${LIB:+$(dirname "$LIB")}"
export PKG_CONFIG_PATH="${PC:+$(dirname "$PC")}"

if [ ! -x "$V" ]; then
    fail "/app/vips/bin/vips is missing or not executable; the project was never installed"
else
    if ! file "$V" | grep -q "ELF"; then
        fail "/app/vips/bin/vips is not an ELF executable"
    fi
    ver=$("$V" --version 2>&1) || ver=""
    case "$ver" in
        *"vips-8.18.6"*) echo "vips binary reports: $ver" ;;
        *) fail "vips --version reported '$ver', expected vips-8.18.6" ;;
    esac
fi

PIPELINE() { # $1 in, $2 a-out, $3 b-out, $4 c-out ; same recipe as instruction
    "$V" rotate "$1" "$2" 90 || return 1
    w=$("$H" -f width "$2") || return 1
    h=$("$H" -f height "$2") || return 1
    "$V" extract_area "$2" "$3" 0 0 $((w / 2)) $((h / 2)) || return 1
    "$V" resize "$3" "$4" 0.5 --kernel nearest || return 1
}

# ---------------------------------------------------------------------------
# 2. /app/out: the six deliverables exist and are pixel-identical to what a
#    run of the same pipeline with the agent's own binary produces.
# ---------------------------------------------------------------------------
if [ ! -d /app/out ]; then
    fail "/app/out does not exist"
fi
for f in vis1-rot90 vis1-crop vis1-half vis2-rot90 vis2-crop vis2-half; do
    if [ ! -f "/app/out/$f.png" ]; then
        fail "deliverable /app/out/$f.png missing"
    fi
done

if [ -d /app/out ]; then
    for stem in vis1 vis2; do
        if ! PIPELINE "/app/fixtures/$stem.png" \
                 "$TMP/$stem-a.png" "$TMP/$stem-b.png" "$TMP/$stem-c.png"; then
            fail "could not recompute visible pipeline for $stem with the installed vips"
            continue
        fi
        for pair in "a rot90" "b crop" "c half"; do
            set -- $pair
            "$V" rawsave "$TMP/$stem-$1.png" "$TMP/$stem-$1.raw" || fail "rawsave $stem-$1"
            "$V" rawsave "/app/out/$stem-$2.png" "$TMP/$stem-$1.agent.raw" || {
                fail "rawsave of /app/out/$stem-$2.png (is it a valid PNG?)"; continue; }
            got=$(md5sum < "$TMP/$stem-$1.raw" | awk '{print $1}')
            agt=$(md5sum < "$TMP/$stem-$1.agent.raw" | awk '{print $1}')
            if [ "$got" != "$agt" ]; then
                fail "visible $stem-$2: /app/out pixels differ from the vips pipeline (recomputed $got vs deliverable $agt)"
            fi
            aw=$("$H" -f width "/app/out/$stem-$2.png" 2>/dev/null || echo "")
            ah=$("$H" -f height "/app/out/$stem-$2.png" 2>/dev/null || echo "")
            ab=$("$H" -f bands "/app/out/$stem-$2.png" 2>/dev/null || echo "")
            rw=$("$H" -f width "$TMP/$stem-$1.png" 2>/dev/null || echo "")
            rh=$("$H" -f height "$TMP/$stem-$1.png" 2>/dev/null || echo "")
            rb=$("$H" -f bands "$TMP/$stem-$1.png" 2>/dev/null || echo "")
            if [ "$aw" != "$rw" ] || [ "$ah" != "$rh" ] || [ "$ab" != "$rb" ]; then
                fail "visible $stem-$2: metadata $aw x $ah x $ab bands, expected $rw x $rh x $rb"
            fi
        done
    done
fi

# ---------------------------------------------------------------------------
# 3. hidden images: the same three operations run with the agent's binary
#    must reproduce the reference pixels (md5 of raw pixel data) and the
#    reference width/height/bands, case by case.
# ---------------------------------------------------------------------------
# md5s computed from an independent reference build of the pinned commit.
REF_MD5="case1-a:09486e74068a68da1768cdbe0523aacf case1-b:f239d5e7b72e86d8927da4ff71d7ea2c case1-c:2edc1a0968f1de5a65ce9c4edd72e3cc
case2-a:3e996ac91aca5da43d829fe8b36aa85a case2-b:c193d291d6a4b232c34f33f69701c3f6 case2-c:062d4b171c8cd892f83787e04992839e
case3-a:b3bbdd63d2495ef38d4e1788e78c711f case3-b:e980d87172eec852e5b4e2a6eea5e531 case3-c:12b3771a5e69b7a0f8e5ca893ac41152"
REF_DIMS="case1-a:40x64 case1-b:20x32 case1-c:10x16
case2-a:36x36 case2-b:18x18 case2-c:9x9
case3-a:34x50 case3-b:17x25 case3-c:9x13"
ref_md5() { for e in $REF_MD5; do [ "${e%%:*}" = "$1" ] && { echo "${e##*:}"; return 0; }; done; }
ref_dims() { for e in $REF_DIMS; do [ "${e%%:*}" = "$1" ] && { echo "${e##*:}"; return 0; }; done; }

for d in /tests/hidden/*/; do
    c=$(basename "$d")
    [ -f "$d/in.png" ] || { fail "hidden case $c has no in.png"; continue; }
    if ! PIPELINE "$d/in.png" "$TMP/$c-a.png" "$TMP/$c-b.png" "$TMP/$c-c.png"; then
        fail "hidden case $c: pipeline failed with the installed vips"
        continue
    fi
    for op in a b c; do
        "$V" rawsave "$TMP/$c-$op.png" "$TMP/$c-$op.raw" || { fail "hidden $c-$op rawsave failed"; continue; }
        got=$(md5sum < "$TMP/$c-$op.raw" | awk '{print $1}')
        want=$(ref_md5 "$c-$op")
        if [ "$got" != "$want" ]; then
            fail "hidden $c-$op: pixel checksum $got, expected $want"
        fi
        dims=$("$H" -f width "$TMP/$c-$op.png")x$("$H" -f height "$TMP/$c-$op.png")
        bands=$("$H" -f bands "$TMP/$c-$op.png")
        wdims=$(ref_dims "$c-$op")
        if [ "$dims" != "$wdims" ] || [ "$bands" != "4" ]; then
            fail "hidden $c-$op: header $dims x $bands bands, expected $wdims x 4 bands"
        fi
    done
done

# ---------------------------------------------------------------------------
# 4. a hidden C program, compiled against the agent-installed library, must
#    reproduce the same pipeline through the vips C API and the reference
#    FNV checksums over the raw pixels.
# ---------------------------------------------------------------------------
cat > "$TMP/probe.c" <<'CEOF'
#include <vips/vips.h>
#include <stdio.h>
#include <stdlib.h>
static int fail(const char *where) {
    fprintf(stderr, "probe: fail at %s: %s\n", where, vips_error_buffer());
    return 1;
}
static int run(const char *path) {
    VipsImage *in = vips_image_new_from_file(path, NULL);
    if (!in) return fail("open");
    VipsImage *rot = NULL;
    if (vips_rotate(in, &rot, 90, NULL) != 0) return fail("rotate");
    VipsImage *crop = NULL;
    if (vips_crop(rot, &crop, 0, 0, rot->Xsize / 2, rot->Ysize / 2, NULL) != 0)
        return fail("crop");
    VipsImage *sz = NULL;
    if (vips_resize(crop, &sz, 0.5, "kernel", VIPS_KERNEL_NEAREST, NULL) != 0)
        return fail("resize");
    size_t n = 0;
    guchar *px = (guchar *) vips_image_write_to_memory(sz, &n);
    if (!px) return fail("memory");
    unsigned int h = 2166136261u;
    for (size_t k = 0; k < n; k++) { h ^= px[k]; h *= 16777619u; }
    fprintf(stdout, "FNV%08x %dx%d b%d n%zu\n", h, sz->Xsize, sz->Ysize,
            sz->Bands, n);
    return 0;
}
int main(int argc, char **argv) {
    if (vips_init(argv[0]) != 0) return fail("init");
    for (int i = 1; i < argc; i++)
        if (run(argv[i])) return 1;
    return 0;
}
CEOF
if ! cc -o "$TMP/probe" "$TMP/probe.c" $(pkg-config --cflags --libs vips) \
        2> "$TMP/gcc.log"; then
    fail "hidden C program did not compile/link against /app/vips (pkg-config says: $(cat "$TMP/gcc.log" | head -n2 | tr '\n' ' '))"
else
    REFC="case1:a8134ffe case2:598a8325 case3:f47c867c"
    refc() { for e in $REFC; do [ "${e%%:*}" = "$1" ] && { echo "${e##*:}"; return 0; }; done; }
    for d in /tests/hidden/*/; do
        c=$(basename "$d")
        out=$("$TMP/probe" "$d/in.png" 2>&1) || out=""
        fnv=$(printf '%s\n' "$out" | sed -n 's/.*FNV\([0-9a-f]\{8\}\).*/\1/p')
        want=$(refc "$c")
        if [ "$fnv" != "$want" ]; then
            fail "hidden $c: C-program checksum got '$fnv', expected $want (probe said: $out)"
        fi
    done
fi

# ---------------------------------------------------------------------------
rm -rf "$TMP"
if [ "$FAILS" = "1" ]; then
    echo "VERIFIER: one or more checks failed (see FAIL lines above)" >&2
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi
echo "VERIFIER: all checks passed"
echo 1 > /logs/verifier/reward.txt
exit 0