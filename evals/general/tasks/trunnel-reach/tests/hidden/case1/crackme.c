#include <unistd.h>
#include <stdint.h>
#include <stdio.h>

static uint32_t rotl(uint32_t v, int n) { return (v << n) | (v >> (32 - n)); }

static const uint32_t KEYS[16] = {
    0x239d9626u, 0x87f9afd9u, 0x5324f453u, 0x777fb3c5u, 0x63f20941u, 0x10fede02u, 0x6b1b6d3au, 0x6bf8a872u, 0x8ab78f9cu, 0x8ee237f1u, 0xf50b02d6u, 0xddc4ad58u, 0x0815b083u, 0x801a34f2u, 0xf2e5d57bu, 0x8a9692beu,
};

int main(void) {
    unsigned char buf[16];
    ssize_t n = read(0, buf, 16);
    if (n != 16) { puts("ACCESS DENIED"); return 1; }
    for (int i = 0; i < 16; i++) {
        if (buf[i] < 0x20 || buf[i] > 0x7e) { puts("ACCESS DENIED"); return 1; }
    }
    uint32_t acc = 0x811c9dc5u ^ 0xd12a0b42u;
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
    if (acc == 0x63cd1775u) { puts("ACCESS GRANTED"); return 0; }
    puts("ACCESS DENIED");
    return 1;
}
