#include "tags.h"

int tag_valid(const char *tag) {
    if (!tag || !(*tag >= 'a' && *tag <= 'z')) {
        return 0;
    }
    const char *p = tag + 1;
    while (*p) {
        char c = *p;
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) {
            return 0;
        }
        p++;
    }
    return 1;
}

int parse_long(const char *s, long *out) {
    if (!s || !*s) {
        return 0;
    }
    const char *p = s;
    int neg = 0;
    if (*p == '-') {
        neg = 1;
        p++;
    }
    if (!(*p >= '0' && *p <= '9')) {
        return 0;
    }
    long v = 0;
    while (*p >= '0' && *p <= '9') {
        v = v * 10 + (*p - '0');
        p++;
    }
    if (*p != '\0') {
        return 0;
    }
    *out = neg ? -v : v;
    return 1;
}
