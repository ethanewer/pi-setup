#include <stdio.h>
#include <string.h>

int main(void) {
    char s[] = "The quick brown fox";
    for (int i = 0; i < (int)strlen(s); i++) {
        if (s[i] >= 'a' && s[i] <= 'z') s[i] -= 32;   /* uppercase in place */
    }
    printf("'%s' len=%lu\n", s, strlen(s));

    unsigned x = 0xdeadbeefu;
    printf("x>>16=%u low8=%u\n", x >> 16, x & 0xffu);
    printf("signext=%d\n", (signed char)0x80);
    printf("-7/2=%d -7%%2=%d\n", -7 / 2, -7 % 2);
    return 0;
}