#!/bin/bash
set -euo pipefail

cat > /app/tricks.c <<'C'
#include <stdio.h>

#define CAT(a, b) a##b
#define Q(x) #x

int the_value = 1;

int main(void) {
    printf("%d %s\n", CAT(the, _value), Q(hello));
    return 0;
}
C

gcc -o /tmp/tricks /app/tricks.c
/tmp/tricks > /app/out.txt