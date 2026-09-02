FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libc6-dev make && rm -rf /var/lib/apt/lists/*

RUN cat > /app/program.c <<'EOF'
#include <stdio.h>
int helper(int x){
    int r = x * 2;
    return r;
}
int main(void){
    int t = helper(1);
    t = helper(3);
    printf("t=%d\n", t);
    if (t > 100) {
        printf("big\n");
    }
    return 0;
}
EOF

RUN cat > /app/Makefile <<'EOF'
run:
	gcc -ftest-coverage -fprofile-arcs program.c -o program
	./program
	gcov program.c
EOF