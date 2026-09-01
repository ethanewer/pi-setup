FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libc6-dev && rm -rf /var/lib/apt/lists/*

RUN cat > /app/vuln.c <<'SRC_END'
#include <stdio.h>

struct session {
    char token[16];
    int  authenticated;
};

int main(void) {
    struct session s;
    s.authenticated = 0;
    char input[64];
    if (fgets(input, sizeof input, stdin) == NULL) {
        return 1;
    }
    /* BUG: this loop copies the input into s.token without bounds-checking.
       The token field is 16 bytes; writing more than 16 bytes overflows into
       the adjacent s.authenticated field. */
    int i;
    for (i = 0; input[i] != '\0' && input[i] != '\n'; ++i) {
        s.token[i] = input[i];
    }
    s.token[i] = '\0';

    if (s.authenticated) {
        printf("ACCESS GRANTED\n");
    } else {
        printf("ACCESS DENIED\n");
    }
    return 0;
}
SRC_END

RUN gcc -O0 -o /app/vuln /app/vuln.c
