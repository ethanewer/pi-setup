#include <unistd.h>
#include <stdint.h>
#include <stdio.h>

static uint32_t rotl(uint32_t v, int n) { return (v << n) | (v >> (32 - n)); }

static const uint32_t KEYS[16] = {
    0xba8c4b3cu, 0x2faf1423u, 0x47ccd5f4u, 0x46de7211u, 0x96e60c55u, 0xa3f02bcdu, 0xba549ca9u, 0x2a34814du, 0xb877c15bu, 0xe0271f1au, 0x381091d4u, 0x26bfe550u, 0xb9c96382u, 0x2b08e661u, 0x5f809809u, 0xb77a5032u,
};

int main(void) {
    unsigned char buf[16];
    ssize_t n = read(0, buf, 16);
    if (n != 16) { puts("ACCESS DENIED"); return 1; }
    for (int i = 0; i < 16; i++) {
        if (buf[i] < 0x20 || buf[i] > 0x7e) { puts("ACCESS DENIED"); return 1; }
    }
    uint32_t acc = 0x811c9dc5u ^ 0x11e17348u;
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
    if (acc == 0x42849409u) { puts("ACCESS GRANTED"); return 0; }
    puts("ACCESS DENIED");
    return 1;
}
