#include <stdio.h>
#include <complex.h>

int main(void) {
    double complex a = 1.0 + 2.0 * I;
    double complex b = 3.0 - 1.0 * I;
    double complex c = a * b;
    printf("a*b = %.2f + %.2fi\n", creal(c), cimag(c));
    double complex m = (a + b) / 2.0;
    printf("mid = %.2f + %.2fi\n", creal(m), cimag(m));
    return 0;
}