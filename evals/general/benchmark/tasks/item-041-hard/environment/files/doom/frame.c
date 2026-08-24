/*
 * doom/frame.c — "DOOM generic" paletted framebuffer renderer for the MIPS port.
 *
 * A DOOM-style renderer reduced to its essence: a fixed paletted framebuffer
 * (one byte per pixel, indexed into a 16-entry grayscale ramp, like the
 * classic 320x200 mode-13h buckets) computed by a simple integer rasterizer,
 * then emitted in a single write() syscall.
 *
 * Wire format of the emitted frame (written to stdout):
 *
 *   offset 0:  u16  magic   (0xE1B0)
 *   offset 2:  u32  marker  (0x444F4F4D, "DOOM" in ASCII)
 *   offset 6:  W*H bytes    row-major framebuffer, row 0 == top scanline
 *
 * Header words are placed into memory with typed stores (memcpy), so their
 * on-disk byte order follows the target CPU endianness.
 *
 * Pixel value for scanline y (0..H-1), column x (0..W-1):
 *
 *   v  = (x*7 + y*13 + ((x*y) >> 2)) % 256
 *   pixel = PALETTE[(v >> 4) & 15]
 */
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#define W 64
#define H 32

/* 16-entry grayscale ramp.  Index (v>>4)&15 selects one of these. */
static const char PALETTE[16] = {
    ' ', '.', ':', '*', 'o', 'O', 'O', 'O',
    '#', '#', '#', '#', '@', '@', '@', '@'
};

int main(void) {
    unsigned char out[2 + 4 + W * H];   /* header + framebuffer */
    int x, y;

    uint16_t magic  = 0xE1B0u;          /* must be emitted big-endian */
    uint32_t marker = 0x444F4F4Du;      /* must be emitted big-endian */
    memcpy(out, &magic, 2);
    memcpy(out + 2, &marker, 4);

    for (y = 0; y < H; y++) {
        for (x = 0; x < W - 1; x++) {
            int v = (x * 7 + y * 13 + ((x * y) >> 2)) % 256;
            int idx = (v >> 4) & 15;
            out[6 + y * W + x] = (unsigned char)PALETTE[idx];
        }
    }

    if (write(1, out, sizeof(out)) != (ssize_t)sizeof(out))
        return 1;
    return 0;
}