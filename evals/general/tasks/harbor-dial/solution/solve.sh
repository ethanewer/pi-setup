#!/bin/bash
# harbor-dial real oracle: authors the three parallel/concurrent subsystems,
# compiles and runs them, and self-checks. Never reads /tests or /solution.
set -eu

# ---------------------------------------------------------------- Part A
cat > /app/pipeline_parallel.py <<'PY'
"""Pipeline-parallel forward/backward over a simulated set of ranks (numpy only).

Layer ids 0..num_layers-1 are owned by pipeline stages, one stage per rank in a
world of num_ranks ranks. Each rank runs its contiguous chunk of layers and hands
the activation tensor to the next rank (and the gradient back in backward).
"""
import numpy as np


def partition(num_layers, num_ranks, rank):
    """Contiguous evenly-split slice of layer indices owned by 'rank'."""
    if not (num_layers >= 0 and num_ranks >= 1 and 0 <= rank < num_ranks):
        raise ValueError("bad partition args")
    lo = (num_layers * rank) // num_ranks
    hi = (num_layers * (rank + 1)) // num_ranks
    return list(range(lo, hi))


def build(num_layers, num_ranks, rank, dims, seed=0, scale=0.1):
    """Return dict {owned_layer_id: (W, b)} for this rank.

    dims has length num_layers+1; W[l] is (dims[l], dims[l+1]), b[l] is
    (dims[l+1],) and all-zero. The RandomState(seed) is advanced across ALL layer
    ids in ascending order regardless of num_ranks, so the same (num_layers,dims,
    seed,scale) build always reproduces identical W per layer (rank-number
    independent)."""
    if len(dims) != num_layers + 1:
        raise ValueError("dims must have length num_layers+1")
    rng = np.random.RandomState(seed)
    full = {}
    for l in range(num_layers):
        W = rng.normal(scale=scale, size=(dims[l], dims[l + 1])).astype(np.float64)
        b = np.zeros(dims[l + 1], dtype=np.float64)
        full[l] = (W, b)
    return {l: full[l] for l in partition(num_layers, num_ranks, rank)}


def stage_forward(block, x):
    """Run one rank's owned layers (ascending) with tanh activations."""
    h = np.asarray(x, dtype=np.float64).copy()
    acts = [h.copy()]
    for l in sorted(block):
        W, b = block[l]
        h = np.tanh(h.dot(W) + b)
        acts.append(h.copy())
    return h, acts


def forward_all(num_layers, num_ranks, full, x):
    """Pipeline forward across every rank; rank r receives rank r-1's output."""
    h = np.asarray(x, dtype=np.float64).copy()
    for r in range(num_ranks):
        chunk = {l: full[l] for l in partition(num_layers, num_ranks, r)}
        h, _ = stage_forward(chunk, h)
    return np.asarray(h, dtype=np.float64)


def backward_all(num_layers, num_ranks, full, x):
    """Gradient of loss = 0.5*sum(forward_all(x)**2) w.r.t. every weight/bias.

    Returns (grads, grad_input): grads[l]=(gradW, gradB), gradW shape
    (dims[l],dims[l+1]), gradB (dims[l+1],); grad_input shape == x.shape."""
    xar = np.asarray(x, dtype=np.float64)
    act, pre = {}, {}
    h = xar
    for r in range(num_ranks):
        for l in partition(num_layers, num_ranks, r):
            W, b = full[l]
            u = h.dot(W) + b
            pre[l] = u
            a = np.tanh(u)
            act[l] = a
            h = a
    d = h.copy()  # gradient w.r.t. final activation (since d/dy 0.5 y^2 = y)
    grads = {}
    for l in range(num_layers - 1, -1, -1):
        a_l = act[l]
        dU = d * (1.0 - a_l * a_l)          # dL / dU_l
        prev = xar if l == 0 else act[l - 1]
        gradW = prev.T.dot(dU)
        gradB = dU.sum(axis=0)
        grads[l] = (gradW, gradB)
        W, _ = full[l]
        d = dU.dot(W.T)                     # gradient flowing to the prior stage
    return grads, d
PY

# ---------------------------------------------------------------- Part B
cat > /app/parallel_assembly.c <<'EOF'
/* harbor-dial: UPC-style shared-heap assembly over pthreads.
 * Usage: pgen <num_ranks>=1> <total_items>>=0
 * Rank r owns slice [lo,hi) of [0,total_items); each worker stores value(i) into
 * the shared heap and accumulates its slice total, then emits rank_<r>.out.
 * Exits 0 only if the shared grand total matches the closed-form sum. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <pthread.h>

static long total_items, num_ranks;
static long *heap;                       /* shared heap: one cell per item */
static long grand_total = 0;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static long item_value(long i){ return (i * 1733L + 17L) % 10007L; }

static void slice(long r, long *lo, long *hi){
    *lo = (total_items * r) / num_ranks;
    *hi = (total_items * (r + 1)) / num_ranks;
}

static void *worker(void *arg){
    long r = (long)(intptr_t)arg, lo, hi, i, total = 0;
    slice(r, &lo, &hi);
    for (i = lo; i < hi; i++){ long v = item_value(i); heap[i] = v; total += v; }
    pthread_mutex_lock(&lock); { grand_total += total; }
    pthread_mutex_unlock(&lock);
    char name[64], buf[256];
    snprintf(name, sizeof name, "rank_%ld.out", r);
    snprintf(buf, sizeof buf,
             "rank=%ld\nlo=%ld\nhi=%ld\ncount=%ld\ntotal=%ld\nok=true\n",
             r, lo, hi, hi - lo, total);
    FILE *f = fopen(name, "w");
    if (!f){ fprintf(stderr, "cannot open %s\n", name); return (void*)1; }
    fputs(buf, f); fclose(f);
    return NULL;
}

int main(int argc, char **argv){
    if (argc != 3){ fprintf(stderr, "usage: %s <num_ranks> <total_items>\n", argv[0]); return 2; }
    num_ranks = atol(argv[1]); total_items = atol(argv[2]);
    if (num_ranks < 1 || total_items < 0){
        fprintf(stderr, "invalid arguments: num_ranks=%ld total_items=%ld\n", num_ranks, total_items);
        return 2;
    }
    heap = (long*)malloc(sizeof(long) * (size_t)total_items);
    if (total_items > 0 && !heap){ fprintf(stderr, "malloc failed\n"); return 2; }
    pthread_t *t = (pthread_t*)malloc(sizeof(pthread_t) * (size_t)num_ranks);
    long r;
    for (r = 0; r < num_ranks; r++)
        if (pthread_create(&t[r], NULL, worker, (void*)(intptr_t)r) != 0) return 2;
    int bad = 0;
    for (r = 0; r < num_ranks; r++){ void *ret; pthread_join(t[r], &ret); if (ret) bad = 1; }
    long expect = 0, i;
    for (i = 0; i < total_items; i++) expect += item_value(i);
    free(t); free(heap);
    if (bad || grand_total != expect){ fprintf(stderr, "assembly mismatch\n"); return 1; }
    return 0;
}
EOF
gcc -O2 -pthread -o /app/pgen /app/parallel_assembly.c

# Produce the visible per-rank deliverable set from /app.
cd /app
rm -f rank_*.out
./pgen 3 21

# ---------------------------------------------------------------- Part C
cat > /app/asyncio_pool.py <<'PY'
"""Max-concurrency-gated asyncio task scheduler."""
import asyncio


class AsyncPool:
    def __init__(self, max_concurrent):
        if max_concurrent < 1:
            raise ValueError("max_concurrent must be >= 1")
        self.max_concurrent = int(max_concurrent)

    async def map(self, coros):
        coros = list(coros)
        sem = asyncio.Semaphore(self.max_concurrent)

        async def run(c):
            async with sem:
                return await c

        return await asyncio.gather(*(run(c) for c in coros))


async def run_capped(coros, max_concurrent):
    return await AsyncPool(max_concurrent).map(coros)
PY

# ------------------------------------------------------- oracle self-check
python3 - <<'PY'
import asyncio, numpy as np, sys
sys.path.insert(0, "/app")
import asyncio_pool

# pipeline mini random check
import pipeline_parallel as pp
L,R,dims = 6,3,[4,5,6,7,5,3,9]
full = {}
for r in range(R):
    for l,v in pp.build(L,R,r,dims,seed=1).items():
        full[l]=v
x = np.random.RandomState(0).randn(2,dims[0])
y = pp.forward_all(L,R,full,x)
assert y.shape == (2,dims[-1])
grads,_ = pp.backward_all(L,R,full,x)
gh = x.copy()
for l in range(L):
    W,b=full[l]; gh=np.tanh(gh.dot(W)+b); 
assert np.max(np.abs(y-gh)) < 1e-9
print("pipeline self-check ok")

# asyncio check
async def chk():
    active=0; mx=0
    async def job(i,d):
        nonlocal active,mx; active+=1; mx=max(mx,active); await asyncio.sleep(d); active-=1; return i
    res = await asyncio_pool.run_capped([job(i,0.01) for i in range(6)],2)
    return res, mx
res,mx = asyncio.run(chk())
assert res==list(range(6)) and mx<=2
print("asyncio self-check ok")
PY

# final deliverables present. The visible `./pgen 3 21` run from /app must
# have written the per-rank output deliverable set /app/rank_*.out.
for f in /app/pipeline_parallel.py /app/parallel_assembly.c /app/pgen /app/asyncio_pool.py; do
    test -f "$f" || { echo "missing $f"; exit 1; }
done
ls /app/rank_*.out >/dev/null 2>&1 || { echo "missing /app/rank_*.out deliverables"; exit 1; }
echo "solution ok"