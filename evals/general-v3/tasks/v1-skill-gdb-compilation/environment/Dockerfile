FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libc6-dev gdb && rm -rf /var/lib/apt/lists/*

RUN cat > /app/debug.c <<'EOF'
#include <stdio.h>
int mix(int a, int b, int c){
    int r = a*3 + b - c;
    return r;
}
int main(void){
    int x1 = 7;
    int x2 = 2;
    int base = mix(x1, x2, 5);
    int checksum = (base * 4) + (x1 % x2) - ((base >> 1) & 0xF);
    printf("hid=%d\n", checksum);
    return 0;
}
EOF