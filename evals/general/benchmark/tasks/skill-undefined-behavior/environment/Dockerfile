FROM bench-base:ubuntu-24.04

WORKDIR /app

# GCC is required to build the C program.
RUN apt-get update && apt-get install -y gcc libc6-dev && rm -rf /var/lib/apt/lists/*

RUN cat > /app/ub.c <<'EOF'
#include <stdio.h>
int main(void) {
    int a = 1;
    int b;                 /* TODO(bug): b is never initialized -> undefined behavior */
    int total = a + b;
    printf("total=%d\n", total);
    return 0;
}
EOF