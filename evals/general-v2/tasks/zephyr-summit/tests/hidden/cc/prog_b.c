#include <stdio.h>
int main(void){ int a = 1, b = 1, c = 0, n; for (n = 3; n <= 12; n++){ c = a + b; a = b; b = c; } printf("%d\n", c); return 0; }
