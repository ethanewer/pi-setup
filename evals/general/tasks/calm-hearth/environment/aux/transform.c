/* calm-hearth FFI transform library (aux build source -- NOT shipped to the
 * agent as source; compiled into /app/libtransform.so during image build). */
#include <stdint.h>
#include <stddef.h>

/* In-place transform: buf[i] = (buf[i]*31 + 17) & 0xff.
 * Returns the 64-bit signed sum of the transformed bytes + 424242. */
int64_t scramble_hill(uint8_t *buf, size_t n) {
    int64_t s = 0;
    for (size_t i = 0; i < n; i++) {
        uint8_t v = (uint8_t)(((uint32_t)buf[i] * 31u + 17u) & 0xffu);
        buf[i] = v;
        s += (int64_t)v;
    }
    s += 424242;
    return s;
}