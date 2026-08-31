#!/bin/bash
# marble-relay oracle: author the relay source (minimal JSON parser + frame
# protocol), compile the native /app/bin/relay deliverable, write the launcher
# manifest /app/relay.json, and smoke-boot through the shipped launcher.
# Never reads /tests.
set -euo pipefail

mkdir -p /app/src /app/bin

# ---- 1. manifest deliverable --------------------------------------------- #
cat > /app/relay.json <<'J'
{"entry": "/app/bin/relay"}
J

# ---- 2. relay source + compile -------------------------------------------- #
cat > /app/src/relay.c <<'C'
/* marble-relay: length-prefixed JSON frame relay. libc only. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

#define MAX_FRAME (1u << 22)

/* ---------------- minimal JSON ---------------- */
typedef enum { JNULL, JBOOL, JNUM, JSTR, JARR, JOBJ } JType;
typedef struct JVal JVal;
struct JVal {
    JType t;
    int b;                /* JBOOL */
    double num;           /* JNUM */
    char *str;            /* JSTR */
    int n;                /* JARR count / JOBJ count */
    JVal **items;         /* JARR items / JOBJ values */
    char **keys;          /* JOBJ keys */
};

static void oom(void) { exit(2); }

static JVal *jnew(JType t) {
    JVal *v = calloc(1, sizeof(JVal));
    if (!v) oom();
    v->t = t;
    return v;
}

static void jskip(const char **p) {
    while (**p == ' ' || **p == '\t' || **p == '\n' || **p == '\r') (*p)++;
}

static unsigned int hex4(const char *p) {
    unsigned int v = 0;
    for (int i = 0; i < 4; i++) {
        char c = p[i];
        int d;
        if (c >= '0' && c <= '9') d = c - '0';
        else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
        else return 0xFFFF0000u; /* sentinel: invalid */
        v = v * 16 + (unsigned int)d;
    }
    return v;
}

static char *jstrdup_escaped(const char **pp) {
    const char *p = *pp;
    if (*p != '"') return NULL;
    p++;
    size_t cap = 32, len = 0;
    char *out = malloc(cap);
    if (!out) oom();
    out[0] = '\0';
#define APP(b) do { \
        if (len + 5 >= cap) { cap *= 2; out = realloc(out, cap); if (!out) oom(); } \
        out[len++] = (char)(b); \
    } while (0)
    while (*p && *p != '"') {
        if (*p == '\\') {
            p++;
            char c = *p++;
            unsigned int cp;
            switch (c) {
            case 'n': cp = '\n'; break;
            case 't': cp = '\t'; break;
            case 'r': cp = '\r'; break;
            case 'b': cp = '\b'; break;
            case 'f': cp = '\f'; break;
            case '"': cp = '"'; break;
            case '\\': cp = '\\'; break;
            case '/': cp = '/'; break;
            case 'u': {
                cp = hex4(p);
                if (cp & 0xFFFF0000u) { free(out); return NULL; }
                p += 4;
                if (cp >= 0xD800 && cp <= 0xDBFF && p[0] == '\\' && p[1] == 'u') {
                    unsigned int lo = hex4(p + 2);
                    if (!(lo & 0xFFFF0000u) && lo >= 0xDC00 && lo <= 0xDFFF) {
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                        p += 6;
                    }
                }
                break;
            }
            default: free(out); return NULL;
            }
            if (cp < 0x80) APP(cp);
            else if (cp < 0x800) {
                APP(0xC0 | (cp >> 6)); APP(0x80 | (cp & 0x3F));
            } else if (cp < 0x10000) {
                APP(0xE0 | (cp >> 12)); APP(0x80 | ((cp >> 6) & 0x3F)); APP(0x80 | (cp & 0x3F));
            } else {
                APP(0xF0 | (cp >> 18)); APP(0x80 | ((cp >> 12) & 0x3F));
                APP(0x80 | ((cp >> 6) & 0x3F)); APP(0x80 | (cp & 0x3F));
            }
        } else {
            APP(*p);
            p++;
        }
    }
#undef APP
    if (*p != '"') { free(out); return NULL; }
    p++;
    out[len] = '\0';
    *pp = p;
    return out;
}

static JVal *jparse_value(const char **pp);

static JVal *jparse_object(const char **pp) {
    const char *p = *pp;
    JVal *v = jnew(JOBJ);
    int cap = 8;
    v->keys = malloc(sizeof(char *) * (size_t)cap);
    v->items = malloc(sizeof(JVal *) * (size_t)cap);
    if (!v->keys || !v->items) oom();
    p++; /* { */
    jskip(&p);
    if (*p == '}') { p++; *pp = p; return v; }
    for (;;) {
        jskip(&p);
        char *key = jstrdup_escaped(&p);
        if (!key) return NULL;
        jskip(&p);
        if (*p != ':') return NULL;
        p++;
        JVal *val = jparse_value(&p);
        if (!val) return NULL;
        if (v->n == cap) {
            cap *= 2;
            v->keys = realloc(v->keys, sizeof(char *) * (size_t)cap);
            v->items = realloc(v->items, sizeof(JVal *) * (size_t)cap);
            if (!v->keys || !v->items) oom();
        }
        v->keys[v->n] = key;
        v->items[v->n] = val;
        v->n++;
        jskip(&p);
        if (*p == ',') { p++; continue; }
        if (*p == '}') { p++; *pp = p; return v; }
        return NULL;
    }
}

static JVal *jparse_array(const char **pp) {
    const char *p = *pp;
    JVal *v = jnew(JARR);
    int cap = 8;
    v->items = malloc(sizeof(JVal *) * (size_t)cap);
    if (!v->items) oom();
    p++; /* [ */
    jskip(&p);
    if (*p == ']') { p++; *pp = p; return v; }
    for (;;) {
        JVal *val = jparse_value(&p);
        if (!val) return NULL;
        if (v->n == cap) {
            cap *= 2;
            v->items = realloc(v->items, sizeof(JVal *) * (size_t)cap);
            if (!v->items) oom();
        }
        v->items[v->n++] = val;
        jskip(&p);
        if (*p == ',') { p++; continue; }
        if (*p == ']') { p++; *pp = p; return v; }
        return NULL;
    }
}

static JVal *jparse_value(const char **pp) {
    const char *p = *pp;
    jskip(&p);
    JVal *v = NULL;
    if (*p == '{') {
        v = jparse_object(&p);
    } else if (*p == '[') {
        v = jparse_array(&p);
    } else if (*p == '"') {
        char *s = jstrdup_escaped(&p);
        if (!s) return NULL;
        v = jnew(JSTR);
        v->str = s;
    } else if (!strncmp(p, "true", 4)) {
        v = jnew(JBOOL); v->b = 1; p += 4;
    } else if (!strncmp(p, "false", 5)) {
        v = jnew(JBOOL); v->b = 0; p += 5;
    } else if (!strncmp(p, "null", 4)) {
        v = jnew(JNULL); p += 4;
    } else {
        char *end;
        double d = strtod(p, &end);
        if (end == p) return NULL;
        v = jnew(JNUM);
        v->num = d;
        p = end;
    }
    if (!v) return NULL;
    *pp = p;
    return v;
}

static JVal *jget(JVal *obj, const char *key) {
    if (!obj || obj->t != JOBJ) return NULL;
    for (int i = 0; i < obj->n; i++)
        if (strcmp(obj->keys[i], key) == 0) return obj->items[i];
    return NULL;
}

/* ---------------- frame IO ---------------- */
static int read_full(unsigned char *buf, size_t n) {
    size_t got = 0;
    while (got < n) {
        size_t r = fread(buf + got, 1, n - got, stdin);
        if (r == 0) return 0;
        got += r;
    }
    return 1;
}

static void send_json(const char *s) {
    uint32_t len = (uint32_t)strlen(s);
    unsigned char head[4];
    head[0] = (unsigned char)(len >> 24);
    head[1] = (unsigned char)(len >> 16);
    head[2] = (unsigned char)(len >> 8);
    head[3] = (unsigned char)(len & 0xFF);
    fwrite(head, 1, 4, stdout);
    fwrite(s, 1, len, stdout);
    fflush(stdout);
}

/* ---------------- replies ---------------- */
static char RBUF[1 << 16];

static void reply_err(const char *code) {
    snprintf(RBUF, sizeof RBUF, "{\"type\":\"error\",\"code\":\"%s\"}", code);
    send_json(RBUF);
}

static int jll(JVal *v, long long *out) {
    if (!v || v->t != JNUM) return 0;
    double d = v->num;
    if (d != (double)(long long)d) return 0;
    *out = (long long)d;
    return 1;
}

static int int_array(JVal *arr, long long **out, int *nout) {
    if (!arr || arr->t != JARR) return 0;
    long long *a = malloc(sizeof(long long) * (size_t)(arr->n > 0 ? arr->n : 1));
    if (!a) oom();
    for (int i = 0; i < arr->n; i++)
        if (!jll(arr->items[i], &a[i])) { free(a); return 0; }
    *out = a;
    *nout = arr->n;
    return 1;
}

static void reply_ll(const char *key, long long x) {
    snprintf(RBUF, sizeof RBUF, "{\"type\":\"result\",\"%s\":%lld}", key, x);
    send_json(RBUF);
}

static void reply_ll_array(long long *a, int n) {
    size_t o = (size_t)snprintf(RBUF, sizeof RBUF, "{\"type\":\"result\",\"values\":[");
    for (int i = 0; i < n && o < sizeof RBUF - 32; i++)
        o += (size_t)snprintf(RBUF + o, sizeof RBUF - o, "%s%lld", i ? "," : "", a[i]);
    snprintf(RBUF + o, sizeof RBUF - o, "]}");
    send_json(RBUF);
}

static int cmp_ll(const void *x, const void *y) {
    long long a = *(const long long *)x, b = *(const long long *)y;
    return (a > b) - (a < b);
}

static void handle(JVal *req) {
    JVal *tv = jget(req, "type");
    if (tv && tv->t == JSTR && strcmp(tv->str, "hello") == 0) {
        send_json("{\"type\":\"ready\",\"proto\":1}");
        return;
    }
    JVal *opv = jget(req, "op");
    if (!opv || opv->t != JSTR) { reply_err("bad-op"); return; }
    const char *op = opv->str;
    JVal *arr = jget(req, "values");

    if (strcmp(op, "sum") == 0 || strcmp(op, "prod") == 0 ||
        strcmp(op, "minmax") == 0 || strcmp(op, "uniq") == 0 || strcmp(op, "rev") == 0) {
        long long *a = NULL; int n = 0;
        if (!int_array(arr, &a, &n)) { reply_err("bad-value"); return; }
        if (strcmp(op, "sum") == 0) {
            long long s = 0;
            for (int i = 0; i < n; i++) s += a[i];
            reply_ll("value", s);
        } else if (strcmp(op, "prod") == 0) {
            long long p = 1;
            for (int i = 0; i < n; i++) p *= a[i];
            reply_ll("value", p);
        } else if (strcmp(op, "minmax") == 0) {
            if (n < 1) { reply_err("bad-value"); free(a); return; }
            long long mn = a[0], mx = a[0];
            for (int i = 1; i < n; i++) {
                if (a[i] < mn) mn = a[i];
                if (a[i] > mx) mx = a[i];
            }
            snprintf(RBUF, sizeof RBUF, "{\"type\":\"result\",\"min\":%lld,\"max\":%lld}", mn, mx);
            send_json(RBUF);
        } else if (strcmp(op, "uniq") == 0) {
            if (n > 1) qsort(a, (size_t)n, sizeof(long long), cmp_ll);
            int m = 0;
            for (int i = 0; i < n; i++)
                if (m == 0 || a[i] != a[m - 1]) a[m++] = a[i];
            reply_ll_array(a, m);
        } else { /* rev */
            for (int i = 0; i < n / 2; i++) {
                long long t = a[i]; a[i] = a[n - 1 - i]; a[n - 1 - i] = t;
            }
            reply_ll_array(a, n);
        }
        free(a);
        return;
    }

    if (strcmp(op, "fnv1a") == 0) {
        JVal *tv2 = jget(req, "text");
        if (!tv2 || tv2->t != JSTR) { reply_err("bad-value"); return; }
        uint32_t h = 2166136261u;
        for (const unsigned char *b = (const unsigned char *)tv2->str; *b; b++) {
            h ^= *b;
            h *= 16777619u;
        }
        snprintf(RBUF, sizeof RBUF, "{\"type\":\"result\",\"value\":%u}", (unsigned)h);
        send_json(RBUF);
        return;
    }

    if (strcmp(op, "delay") == 0) {
        long long ms;
        if (!jll(jget(req, "ms"), &ms) || ms < 1 || ms > 300) { reply_err("bad-value"); return; }
        struct timespec ts = { (time_t)(ms / 1000), (long)(ms % 1000) * 1000000L };
        nanosleep(&ts, NULL);
        reply_ll("value", ms);
        return;
    }

    reply_err("bad-op");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    for (;;) {
        unsigned char head[4];
        if (!read_full(head, 4)) return 0; /* EOF: clean shutdown */
        uint32_t len = ((uint32_t)head[0] << 24) | ((uint32_t)head[1] << 16) |
                       ((uint32_t)head[2] << 8) | (uint32_t)head[3];
        if (len > MAX_FRAME) return 1;
        char *payload = malloc((size_t)len + 1);
        if (!payload) oom();
        if (!read_full((unsigned char *)payload, len)) return 0;
        payload[len] = '\0';
        const char *cur = payload;
        JVal *req = jparse_value(&cur);
        if (req) handle(req);
        else reply_err("bad-op");
        free(payload);
    }
}
C

gcc -O2 -Wall -o /app/bin/relay /app/src/relay.c
chmod 0755 /app/bin/relay

# ---- 3. smoke boot through the shipped launcher --------------------------- #
mkdir -p /tmp/mr-smoke
node -e '
const fs = require("fs");
const caseDoc = { queries: [
  { send: { op: "sum", values: [1, 2, 3] }, expect: { type: "result", value: 6 } },
  { send: { op: "fnv1a", text: "smoke" }, expect: { type: "result", value: 1611018502 } },
] };
fs.writeFileSync("/tmp/mr-smoke/case.json", JSON.stringify(caseDoc));
'
out=$(node /app/launcher.js /tmp/mr-smoke/case.json)
echo "smoke: $out"
echo "$out" | grep -q ALL_OK || { echo "smoke boot failed: $out" >&2; exit 1; }

echo "solve.sh done -> /app/bin/relay and /app/relay.json"
ls -l /app/bin/relay /app/relay.json
