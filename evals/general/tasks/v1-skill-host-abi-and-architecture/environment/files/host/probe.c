#include <stdio.h>

int main(void) {
    unsigned int x = 0x01020304;
    const char* p = (const char*)&x;
    const char* endian = (p[0] == 0x04) ? "LE" : "BE";
    printf("ARCH=%d ENDIAN=%s POINTER=%d\n",
           (int)(sizeof(void*) * 8),
           endian,
           (int)sizeof(void*));
    return 0;
}