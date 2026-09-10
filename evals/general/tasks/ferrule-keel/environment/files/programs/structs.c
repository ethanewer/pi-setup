#include <stdio.h>

typedef struct {
    char c;
    int i;
    double d;
} S;

typedef struct {
    unsigned int a : 3;
    unsigned int b : 5;
    unsigned int c : 8;
} B;

union U {
    unsigned int u;
    float f;
};

int main(void) {
    S s = { 'x', 123456, 3.25 };
    printf("sizeof(S)=%zu off(i)=%zu\n",
           sizeof(S), (size_t)((char *)&s.i - (char *)&s));
    printf("c=%c i=%d d=%.2f\n", s.c, s.i, s.d);

    B b = { 5, 21, 200 };
    printf("bitfield a=%u b=%u c=%u sizeof=%zu\n",
           b.a, b.b, b.c, sizeof(b));

    union U u;
    u.u = 1065353216u;                       /* 0x3F800000 == 1.0f */
    printf("ints-as-float: 0x%X = %f\n", u.u, (double)u.f);

    printf("%d %d %d %d\n", 1 << 3, 256 >> 3, -256 >> 3, 7 & 3);
    return 0;
}