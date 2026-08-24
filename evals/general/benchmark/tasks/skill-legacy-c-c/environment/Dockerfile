FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

RUN cat > /app/legacy.c <<'EOF'
#include <stdio.h>

int main(void) {
    char c = 'A';
    int i = 10;
    printf("%c %s\n", i, c);   /* format/argument mismatch (bug) */
    return 0;
}
EOF