FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libc6-dev gdb binutils && rm -rf /var/lib/apt/lists/*

RUN cat > /app/gen.c <<'EOF'
#include <stdio.h>
#include <string.h>
int main(void){
    char secret[] = "OBJD-REVEAL-77";
    long h = 0;
    for (int i = 0; secret[i]; i++)
        h = h * 31 + secret[i];
    printf("hash=%ld\n", h);
    return 0;
}
EOF

RUN gcc -g -O2 /app/gen.c -o /app/mystery
RUN rm /app/gen.c