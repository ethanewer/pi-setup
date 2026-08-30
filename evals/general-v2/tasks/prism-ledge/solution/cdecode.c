/* cdecode - decode an 8-bit grayscale PNG and print its pixel matrix.
 *
 * Usage: cdecode <input.png>
 *
 * Prints one row per line, `width` space-separated integers per line, values
 * in [0,255] being the 8-bit gray sample of each pixel in row-major order.
 * Handles grayscale (and converts palette/RGB to gray) PNGs, both 8-bit and
 * expanded 1/2/4-bit, stripping 16-bit to 8-bit. This is the low-level reader
 * that feeds the classifier, so values are the raw samples (no gamma/blend).
 */
#include <png.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: cdecode <input.png>\n");
        return 2;
    }
    FILE *fp = fopen(argv[1], "rb");
    if (!fp) {
        fprintf(stderr, "cannot open %s\n", argv[1]);
        return 3;
    }
    png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png) { fclose(fp); return 4; }
    png_infop info = png_create_info_struct(png);
    png_infop end = png_create_info_struct(png);
    if (!info || !end) {
        png_destroy_read_struct(&png, &info, &end);
        fclose(fp);
        return 4;
    }
    if (setjmp(png_jmpbuf(png))) {
        png_destroy_read_struct(&png, &info, &end);
        png_destroy_info_struct(png, &end);
        png_destroy_read_struct(&png, &info, NULL);
        fclose(fp);
        fprintf(stderr, "png decode error\n");
        return 5;
    }
    png_init_io(png, fp);
    png_read_info(png, info);

    png_uint_32 width = png_get_image_width(png, info);
    png_uint_32 height = png_get_image_height(png, info);
    int bit_depth = png_get_bit_depth(png, info);
    int color_type = png_get_color_type(png, info);

    /* Normalise to 8-bit grayscale. */
    if (color_type == PNG_COLOR_TYPE_PALETTE)
        png_set_palette_to_rgb(png);
    if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8)
        png_set_expand_gray_1_2_4_to_8(png);
    if (bit_depth == 16)
        png_set_strip_16(png);
    if (color_type == PNG_COLOR_TYPE_RGB || color_type == PNG_COLOR_TYPE_RGB_ALPHA ||
        color_type == PNG_COLOR_TYPE_PALETTE)
        png_set_rgb_to_gray(png, 1, -1, -1);   /* weight: default lum weights */

    png_read_update_info(png, info);
    png_size_t rowbytes = png_get_rowbytes(png, info);
    png_uint_32 out_width = png_get_image_width(png, info);
    png_uint_32 out_height = png_get_image_height(png, info);

    png_bytep *rows = malloc(sizeof(png_bytep) * out_height);
    for (png_uint_32 y = 0; y < out_height; y++)
        rows[y] = malloc(rowbytes);
    png_read_image(png, rows);
    png_read_end(png, end);

    for (png_uint_32 y = 0; y < out_height; y++) {
        for (png_uint_32 x = 0; x < out_width; x++) {
            if (x) putchar(' ');
            printf("%d", (int)rows[y][x]);
        }
        putchar('\n');
    }

    for (png_uint_32 y = 0; y < out_height; y++)
        free(rows[y]);
    free(rows);
    png_destroy_read_struct(&png, &info, &end);
    fclose(fp);
    return 0;
}