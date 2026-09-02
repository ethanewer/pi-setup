#!/usr/bin/env bash
set -euo pipefail

# 1. exploit payload: overflow token[16] so bytes 16..19 set authenticated != 0
python3 -c "import sys; sys.stdout.write('A'*20 + '\n')" > /app/payload
/app/vuln < /app/payload | grep -q 'ACCESS GRANTED'

# 2. explanation
cat > /app/explanation.txt <<'TXT_END'
The bug is a buffer overflow on the stack. The copy loop writes the entire input
into the 16-byte token field without checking the length. Because the `authenticated`
int is stored directly after `token` inside the `session` struct, writing 20 bytes of
input overwrites bytes 0..19 and sets `authenticated` to a non-zero value
(0x41414141), which makes the program grant access.
TXT_END

# 3. fixed version
cat > /app/safe.c <<'SRC_END'
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
    /* FIXED: copy at most sizeof(s.token)-1 bytes so the authenticated field is never
       overwritten. */
    int i;
    for (i = 0; i < (int)sizeof(s.token) - 1 && input[i] != '\0' && input[i] != '\n'; ++i) {
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
gcc -O0 -o /app/safe /app/safe.c

! ( /app/safe < /app/payload | grep -q 'ACCESS GRANTED' )
