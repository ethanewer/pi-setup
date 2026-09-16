#include <stdio.h>
#include <complex.h>

int main(void) {
    double complex z = 2.5 + 3.0 * I;
    double complex w = z * conj(z);          /* == |z|^2 */
    printf("z = %.2f + %.2fi\n", creal(z), cimag(z));
    printf("|z|^2 = %.2f\n", creal(w));
    printf("z + I = %.2f + %.2fi\n", creal(z + I), cimag(z + I));
    return 0;
}