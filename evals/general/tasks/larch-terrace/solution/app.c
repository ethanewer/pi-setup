#include <stdio.h>

#define V 23
#define D 8

static int emb(int t, int i) { return (t * 5 + i * 7 + 1) % 9; }
static int w1v(int i, int j) { return (i * 3 + j * 11) % 7 - 3; }
static int b1v(int j)        { return (j * 13) % 5 - 2; }
static int w2v(int j, int k) { return (j * 17 + k * 5) % 7 - 3; }
static int b2v(int k)        { return (k * 3) % 5 - 2; }

static int relu(int x) { return x > 0 ? x : 0; }

/* one forward pass over the whole context; returns arg-max next token id
   (first index on ties) using the documented integer architecture. */
static int next_token(const int *ctx, int n) {
    int c[D], h[D], lo[V];
    int i, j, k, s, best, m;
    for (i = 0; i < D; i++) {
        c[i] = 0;
        for (j = 0; j < n; j++) c[i] += emb(ctx[j], i);
    }
    for (j = 0; j < D; j++) {
        s = b1v(j);
        for (i = 0; i < D; i++) s += c[i] * w1v(i, j);
        h[j] = relu(s);
    }
    for (k = 0; k < V; k++) {
        s = b2v(k);
        for (j = 0; j < D; j++) s += h[j] * w2v(j, k);
        lo[k] = s;
    }
    best = 0; m = lo[0];
    for (k = 1; k < V; k++) if (lo[k] > m) { m = lo[k]; best = k; }
    return best;
}

int main(void) {
    int ctx[512];
    int L, n, i, t, k;
    if (scanf("%d %d", &L, &n) != 2) return 1;
    if (n < 0 || n > 256) n = 0;
    for (i = 0; i < n; i++) {
        if (scanf("%d", &t) != 1) return 1;
        ctx[i] = t;
    }
    for (k = 0; k < L; k++) {
        t = next_token(ctx, n + k);
        ctx[n + k] = t;
        if (k) putchar(' ');
        printf("%d", t);
    }
    putchar('\n');
    return 0;
}