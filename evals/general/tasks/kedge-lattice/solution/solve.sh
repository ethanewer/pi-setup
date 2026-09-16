#!/usr/bin/env bash
# Oracle for kedge-lattice. Does the real work the task requires and creates
# every declared deliverable:
#   1. builds libvips with its own build system and installs it to /app/vips,
#   2. drives the installed vips CLI over the two fixtures -> /app/out,
#   3. proves the install is C-usable by compiling and running a trivial
#      program against it with pkg-config.
# Reads only /app; never touches /tests or /solution. No output bytes are
# hardcoded anywhere.
set -euo pipefail

cd /app/src

# ---- 1. build the project and install it under /app/vips -------------------
meson setup build --prefix=/app/vips -Ddeprecated=false -Dmodules=disabled
meson compile -C build -j1
meson install -C build

# ---- 2. make the installed artifacts usable, then drive the vips CLI --------
LIBDIR=$(find /app/vips/lib -name 'libvips.so.42' -printf '%h\n' | head -n1)
PCDIR=$(find /app/vips/lib -name 'vips.pc' -printf '%h\n' | head -n1)
export LD_LIBRARY_PATH="$LIBDIR"
export PKG_CONFIG_PATH="$PCDIR"

V=/app/vips/bin/vips
H=/app/vips/bin/vipsheader
TMPW=$(mktemp -d)

mkdir -p /app/out
for stem in vis1 vis2; do
    in="/app/fixtures/$stem.png"
    "$V" rotate "$in" "/app/out/$stem-rot90.png" 90
    w=$("$H" -f width "/app/out/$stem-rot90.png")
    h=$("$H" -f height "/app/out/$stem-rot90.png")
    "$V" extract_area "/app/out/$stem-rot90.png" "/app/out/$stem-crop.png" \
        0 0 $((w / 2)) $((h / 2))
    "$V" resize "/app/out/$stem-crop.png" "/app/out/$stem-half.png" \
        0.5 --kernel nearest
done

# ---- 3. sanity: the install must be usable from C via pkg-config ------------
cat > "$TMPW/probe.c" <<'CEOF'
#include <vips/vips.h>
#include <stdio.h>
int main(int argc, char **argv) {
    if (vips_init(argv[0]) != 0)
        return 1;
    if (argc != 2)
        return 2;
    VipsImage *in = vips_image_new_from_file(argv[1], NULL);
    if (in == NULL)
        return 3;
    fprintf(stdout, "probe %dx%d b%d\n", in->Xsize, in->Ysize, in->Bands);
    return 0;
}
CEOF
cc -o "$TMPW/probe" "$TMPW/probe.c" $(pkg-config --cflags --libs vips)
LD_LIBRARY_PATH="$LIBDIR" "$TMPW/probe" /app/fixtures/vis1.png

rm -rf "$TMPW"
echo "oracle: build, install and /app/out complete"
exit 0