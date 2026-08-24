#!/bin/bash
set -euo pipefail

cat > /app/ub.c <<'EOF'
#include <stdio.h>
int main(void) {
    int a = 1;
    int b = 5;
    int total = a + b;
    printf("total=%d\n", total);
    return 0;
}
EOF

gcc -o /app/ub /app/ub.c
/app/ub