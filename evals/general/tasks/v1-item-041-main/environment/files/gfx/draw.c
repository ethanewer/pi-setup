/*
 * gfx/draw.c — "DOOM generic" paletted frame generator for the MIPS port.
 *
 * A DOOM-style WAD-frame generator reduced to its essence: it renders a
 * fixed paletted framebuffer (one byte per pixel, indexed into a 16-entry
 * grayscale ramp, just like the classic mode-13h planar buckets) with a
 * simple integer rasterizer, prefixes a small header with two typed stores,
 * and emits the whole buffer to stdout in a single write() syscall.
 *
 * Wire format of the emitted frame (written to stdout):
 *
 *   offset 0:  u16   magic  = 0x4944   (prints as the two bytes "ID")
 *   offset 2:  u32   marker = 0x50574144 ; prints as the four bytes "PWAD"
 *   offset 6:  W*H bytes      row-major framebuffer, row 0 == top scanline
 *
 * The two header words are placed into memory with typed stores (memcpy),
 * so their on-disk byte order follows the target CPU endianness.  On the
 * required big-endian target the full 6-byte header is exactly the ASCII
 * text:  ID PWAD    (bytes 49 44 50 57 41 44).
 *
 * Pixel value for scanline y (0..H-1), column x (0..W-1):
 *
 *   v     = (x*13 + y*29 + ((x>>1)*(y>>2))) % 256
 *   index = (v >> 4) & 15                  # 0..15
 *   pixel = PALETTE[index]
 *
 * Rows are contiguous: framebuffer byte at out[6 + y*W + x].
 */
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#define W 64
#define H 24

/* 16-entry ASCII ramp.  Index (v>>4)&15 selects one of these. */
static const char PALETTE[16] = {
    ' ', '.', ':', '-', '=', '+', '*', '#',
    '%', '@', '&', 'o', '$', 'O', 'X', 'Y'
};

int main(void) {
    unsigned char out[2 + 4 + W * H];   /* header + framebuffer */
    int x, y;

    uint16_t magic  = 0x4944u;   /* big-endian bytes: 49 44 = "ID" */
    uint32_t marker = 0x50574144u; /* big-endian bytes: 50 57 41 44 = "PWAD" */
    memcpy(out, &magic, 2);
    memcpy(out + 2, &marker, 4);

    for (y = 0; y < H; y++) {
        for (x = 0; x < W - 1; x++) {   /* FIXME: should be x < W */
            int v = (x * 13 + y * 29 + ((x >> 1) * (y >> 2))) % 256;
            int idx = (v >> 4) & 15;
            out[6 + y * W + x] = (unsigned char)PALETTE[idx];
        }
    }

    if (write(1, out, sizeof(out)) != (ssize_t)sizeof(out))
        return 1;
    return 0;
}