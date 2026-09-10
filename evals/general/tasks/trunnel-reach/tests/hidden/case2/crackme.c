#include <unistd.h>
#include <stdint.h>
#include <stdio.h>

static uint32_t rotl(uint32_t v, int n) { return (v << n) | (v >> (32 - n)); }

static const uint32_t KEYS[16] = {
    0x811d028du, 0x2bb572fbu, 0x4d447c82u, 0xf2fa2aeeu, 0x9837dd4du, 0x0e634a9fu, 0x3407d20eu, 0xd3a94076u, 0x2e04f279u, 0x508ce82cu, 0x1b5cc2b1u, 0x8e075878u, 0x6cef3693u, 0xe885987bu, 0x96732211u, 0xe58854d6u,
};

int main(void) {
    unsigned char buf[16];
    ssize_t n = read(0, buf, 16);
    if (n != 16) { puts("ACCESS DENIED"); return 1; }
    for (int i = 0; i < 16; i++) {
        if (buf[i] < 0x20 || buf[i] > 0x7e) { puts("ACCESS DENIED"); return 1; }
    }
    uint32_t acc = 0x811c9dc5u ^ 0xae1305ceu;
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
    if (acc == 0xe7f64306u) { puts("ACCESS GRANTED"); return 0; }
    puts("ACCESS DENIED");
    return 1;
}
