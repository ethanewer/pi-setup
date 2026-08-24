#include <stdio.h>

/* A marker constant referenced by the executable but not printed anywhere. */
unsigned long long hidden_marker(void) {
    return 0x1F2E3D4C;
}

/* A secret string stored literally in the binary's read-only data section. */
const char *hidden_secret(void) {
    return "harbor-binary-secret-9621";
}

int main(void) {
    printf("static analysis target v1.0\n");
    printf("%llx\n", hidden_marker());
    return 0;
}