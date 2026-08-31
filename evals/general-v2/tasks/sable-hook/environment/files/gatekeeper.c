/*
 * gatekeeper: build-time only. Compiled, stripped, and the source removed so
 * only the binary ships in the image. Validates an access passphrase passed
 * as argv[1]; on success prints the deploy secret.
 */
#include <stdio.h>
#include <string.h>

/* access passphrase, XOR-obfuscated with a 4-byte rolling key */
static const unsigned char ENC[14] = {
    0x2e, 0x49, 0x9f, 0x10, 0x29, 0x48, 0x94, 0x19,
    0x77, 0x5a, 0x9b, 0x18, 0x28, 0x58
};
static const unsigned char KEY[4] = { 0x5a, 0x3c, 0xf1, 0x77 };

/* deploy secret, obfuscated with a different 4-byte rolling key */
static const unsigned char DEPLOY_ENC[21] = {
    0xe7, 0x46, 0xc1, 0x62, 0xe5, 0x0a, 0xdb, 0x7e, 0xf4, 0x49, 0x99,
    0x3b, 0xf4, 0x15, 0x85, 0x6d, 0xa8, 0x46, 0x83, 0x6a, 0xa5
};
static const unsigned char DEPLOY_KEY[4] = { 0x91, 0x27, 0xb4, 0x0e };

int main(int argc, char **argv) {
    if (argc != 2) {
        printf("LOCKED\n");
        return 1;
    }
    const unsigned char *s = (const unsigned char *)argv[1];
    size_t n = strlen(argv[1]);
    if (n != sizeof ENC) {
        printf("LOCKED\n");
        return 1;
    }
    for (size_t i = 0; i < n; i++) {
        if ((unsigned char)(s[i] ^ KEY[i % 4]) != ENC[i]) {
            printf("LOCKED\n");
            return 1;
        }
    }
    char tok[32];
    for (size_t i = 0; i < sizeof DEPLOY_ENC; i++) {
        tok[i] = (char)(DEPLOY_ENC[i] ^ DEPLOY_KEY[i % 4]);
    }
    tok[sizeof DEPLOY_ENC] = '\0';
    printf("GRANTED DEPLOY_SECRET=%s\n", tok);
    return 0;
}
