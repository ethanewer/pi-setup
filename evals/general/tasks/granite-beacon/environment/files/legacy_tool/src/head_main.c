#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "core.h"

static char *strip(char *s) {
    while (*s == ' ' || *s == '\t') s++;
    char *e = s + strlen(s);
    while (e > s && (e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\n' || e[-1] == '\r')) e--;
    *e = '\0';
    return s;
}

int main(void) {
    char line[8192];
    while (fgets(line, sizeof line, stdin)) {
        char *colon = strchr(line, ':');
        if (!colon) continue;
        *colon = '\0';
        char *key = strip(line);
        long n = strtol(colon + 1, NULL, 10);
        printf("%s:%ld\n", key, engine_value(n));
    }
    return 0;
}