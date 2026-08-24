FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libc6-dev binutils xxd && rm -rf /var/lib/apt/lists/*

RUN cat > /app/chal.c <<'SRC_END'
#include <stdio.h>
#include <string.h>

/* password "r3v3rs3_m3" XORed byte-wise with KEY (0x2A) */
static const unsigned char key = 42;
static const unsigned char enc[] = {
    0x58, 0x19, 0x5c, 0x19, 0x58, 0x59, 0x19, 0x75, 0x47, 0x19
};
static const int PASS_LEN = 10;

/* "FLAG{rev3rsing_1s_fun}" XORed byte-wise with KEY (0x2A) */
static const unsigned char flag_enc[] = {
    0x6c, 0x66, 0x6b, 0x6d, 0x51, 0x58, 0x4f, 0x5c, 0x19, 0x58,
    0x59, 0x43, 0x44, 0x4d, 0x75, 0x1b, 0x59, 0x75, 0x4c, 0x5f,
    0x44, 0x57, 0x00
};

int main(int argc, char **argv) {
    int i;
    if (argc != 2) {
        printf("usage: %s <password>\n", argv[0]);
        return 1;
    }
    if (strlen(argv[1]) != PASS_LEN) {
        printf("access denied\n");
        return 1;
    }
    for (i = 0; i < PASS_LEN; i++) {
        if (((unsigned char)argv[1][i] ^ key) != enc[i]) {
            printf("access denied\n");
            return 1;
        }
    }
    for (i = 0; flag_enc[i]; i++) {
        printf("%c", flag_enc[i] ^ key);
    }
    printf("\n");
    return 0;
}
SRC_END

RUN gcc -O1 -o /app/chal /app/chal.c && rm /app/chal.c