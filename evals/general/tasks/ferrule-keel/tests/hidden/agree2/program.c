#include <stdio.h>
#include <string.h>

int main(void) {
    char s[] = "racecar";
    int pal = 1;
    for (int i = 0, j = (int)strlen(s) - 1; i < j; i++, j--) {
        if (s[i] != s[j]) pal = 0;
    }
    printf("palindrome=%d\n", pal);

    char t[64];
    strcpy(t, "racecar");
    strcat(t, "!");
    printf("t='%s'\n", t);

    unsigned v = 0xabcd1234u;
    printf("mask=%u %u\n", v & 0xffu, (v >> 24) | (v << 8));
    printf("shifted=%d\n", (int)(v >> 28) & 1 ? 7 : 9);
    return 0;
}