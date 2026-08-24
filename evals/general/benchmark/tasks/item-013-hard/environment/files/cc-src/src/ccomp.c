/* ccomp.c -- the c0 compiler backend delivered by this staged build.
 *
 * LANGUAGE ("clab"): a tiny C-like expression language.
 *   Variable names : single lowercase letters a..z, initially 0.
 *   Statements (one per line):  ID = EXPR ;      (assign)
 *                               put EXPR ;       (print value)
 *   Comments:  // to end of line (ignored anywhere).
 *   EXPR := TERM (('+'|'-') TERM)*
 *   TERM := FACTOR ('*' FACTOR)*
 *   FACTOR := INT | ID | '(' EXPR ')'
 *   Precedence: '*' binds tighter than '+'/'-'; left-associative.
 *   Values are signed 64-bit, no wraparound on the graded inputs.
 * INPUTS ARE GUARANTEED VALID.  No other tokens/operators appear.
 *
 * OUTPUT: line 1 is the deployment header "; wordsize <C0_WORDSIZE>";
 * then, for each 'put' statement in order, one line with the decimal value.
 *
 * EDIT BOUNDARY: this backend may be edited freely, but it must remain a
 * single self-contained C file including only <stdio.h> <stdlib.h>
 * <string.h> <ctype.h> and "machine.h"; it must keep the documented language
 * and output contract exactly, and must compile cleanly as
 *     gcc -O1 -Ibuild -o build/c0 src/ccomp.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "machine.h"

#define MAXSTMT 4096

static long long vars[26];

static char *skipws(char *p) {
    for (;;) {
        while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
        if (p[0] == '/' && p[1] == '/') {
            p += 2;
            while (*p && *p != '\n') p++;
        } else break;
    }
    return p;
}

static long long term(char **pp);
static long long factor(char **pp);

static long long expr(char **pp) {
    char *p = *pp;
    long long v = term(&p);
    for (;;) {
        char *q = skipws(p);
        if (*q == '+') { q++; v = v + term(&q); p = q; }
        else if (*q == '-') { q++; v = v - term(&q); p = q; }
        else { p = q; break; }
    }
    *pp = p;
    return v;
}

static long long term(char **pp) {
    char *p = *pp;
    long long v = factor(&p);
    for (;;) {
        char *q = skipws(p);
        if (*q == '*') { q++; v = v * factor(&q); p = q; }
        else { p = q; break; }
    }
    *pp = p;
    return v;
}

static long long factor(char **pp) {
    char *p = skipws(*pp);
    long long v;
    if (*p == '(') {
        p++;
        v = expr(&p);
        p = skipws(p);
        if (*p == ')') p++;
        *pp = p;
        return v;
    }
    if (islower((unsigned char)*p)) {
        v = vars[*p - 'a'];
        *pp = p + 1;
        return v;
    }
    if (isdigit((unsigned char)*p)) {
        v = 0;
        while (isdigit((unsigned char)*p)) { v = v * 10 + (*p - '0'); p++; }
        *pp = p;
        return v;
    }
    *pp = p;
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    FILE *in = fopen(argv[1], "r");
    if (!in) return 3;
    FILE *out = fopen(argv[2], "w");
    if (!out) { fclose(in); return 3; }
    int orphan = 0; /* unused sentinel; benign but the build flags it */

    fseek(in, 0, SEEK_END);
    long sz = ftell(in);
    fseek(in, 0, SEEK_SET);
    char *buf = malloc(sz + 1);
    if (!buf) { fclose(in); fclose(out); return 3; }
    fread(buf, 1, (size_t)sz, in);
    buf[sz] = '\0';
    fclose(in);

    memset(vars, 0, sizeof(vars));

    fprintf(out, "; wordsize %d\n", (int)C0_WORDSIZE);

    char *p = buf;
    while (*p) {
        p = skipws(p);
        if (!*p) break;
        if (strncmp(p, "put", 3) == 0 && (p[3] == ' ' || p[3] == '\t' || p[3] == '(')) {
            char *q = p + 3;
            long long val = expr(&q);
            fprintf(out, "%lld\n", val);
            q = skipws(q);
            if (*q == ';') q++;
            p = q;
        } else if (islower((unsigned char)*p)) {
            int id = *p - 'a';
            p++;
            p = skipws(p);
            if (*p == '=') {
                p++;
                vars[id] = expr(&p);
                p = skipws(p);
                if (*p == ';') p++;
            } else {
                while (*p && *p != '\n') p++;
            }
        } else {
            while (*p && *p != '\n') p++;
        }
    }
    free(buf);
    fclose(out);
    return 0;
}
