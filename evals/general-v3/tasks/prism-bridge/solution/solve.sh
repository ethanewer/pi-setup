#!/usr/bin/env bash
# Oracle for prism-bridge. Authors both deliverables by doing the real work,
# installs the pinned hadoop/java stack, then self-checks everything.
set -euo pipefail
cd /app

# --- deliverable 1: MPI contig assembler source ---------------------------
cat > /app/mpi_main.c <<'MPIC'
/* prism-bridge : MPI contig assembler.
 *
 * Reads a fragment file (one line per fragment:  CHAIN_ID<TAB>FRAGMENT ),
 * groups fragments by chain id, assembles each chain independently with a
 * deterministic greedy suffix/prefix-overlap merge, and writes one assembled
 * contig per line for the chains owned by this rank.
 *
 * Usage: mpi_sim <input.txt> <outdir>
 *   Rank r owns chains where  chain_id % size == r  and writes
 *   <outdir>/contigs.rank<r>.txt .  Rank 0 reads the file, sends every
 *   non-root rank its owned chains over MPI, then assembles its own share.
 *   For size==1 rank 0 assembles every chain.
 */
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define MAXLINE 8192

/* ---------- generic dynamic byte vector ---------- */
typedef struct { unsigned char *b; size_t len, cap; } Vec;
static void vec_reserve(Vec *v, size_t extra) {
    if (v->len + extra > v->cap) {
        size_t nc = v->cap ? v->cap : 256;
        while (nc < v->len + extra) nc *= 2;
        v->b = realloc(v->b, nc);
        v->cap = nc;
    }
}
static void vec_append(Vec *v, const void *src, size_t n) {
    vec_reserve(v, n);
    memcpy(v->b + v->len, src, n);
    v->len += n;
}
static void pack_u32(Vec *v, unsigned x) {
    unsigned char t[4] = { (x >> 24) & 0xff, (x >> 16) & 0xff, (x >> 8) & 0xff, x & 0xff };
    vec_append(v, t, 4);
}
static unsigned unpack_u32(const unsigned char *p) {
    return ((unsigned)p[0] << 24) | ((unsigned)p[1] << 16) | ((unsigned)p[2] << 8) | p[3];
}

/* ---------- fragment / piece holders ---------- */
typedef struct { char *f; int len; } Frag;
typedef struct { Frag *a; int n, cap; } Frags;

static void frags_push(Frags *g, const char *s, int len) {
    if (g->n == g->cap) {
        g->cap = g->cap ? g->cap * 2 : 8;
        g->a = realloc(g->a, (size_t)g->cap * sizeof(Frag));
    }
    char *cp = malloc(len + 1);
    memcpy(cp, s, len);
    cp[len] = 0;
    g->a[g->n].f = cp;
    g->a[g->n].len = len;
    g->n++;
}

typedef struct { char *s; int len; } Piece;
typedef struct { Piece *p; int n, cap; } Pieces;
static void pieces_push(Pieces *g, const char *s, int len) {
    if (g->n == g->cap) {
        g->cap = g->cap ? g->cap * 2 : 8;
        g->p = realloc(g->p, (size_t)g->cap * sizeof(Piece));
    }
    char *cp = malloc(len + 1);
    memcpy(cp, s, len);
    cp[len] = 0;
    g->p[g->n].s = cp;
    g->p[g->n].len = len;
    g->n++;
}
static void pieces_remove(Pieces *g, int idx) {
    free(g->p[idx].s);
    for (int i = idx; i + 1 < g->n; i++) g->p[i] = g->p[i + 1];
    g->n--;
}
static void pieces_free(Pieces *g) {
    for (int i = 0; i < g->n; i++) free(g->p[i].s);
    free(g->p);
    g->p = NULL; g->n = g->cap = 0;
}

/* max k such that the length-k suffix of a equals the length-k prefix of b */
static int overlap(const char *a, int la, const char *b, int lb) {
    int m = la < lb ? la : lb;
    for (int k = m; k >= 1; k--)
        if (memcmp(a + la - k, b, k) == 0) return k;
    return 0;
}

/* Assemble all fragments of a chain into contigs pushed onto `out`. */
static void assemble_frags(Frags *g, Pieces *out) {
    Pieces P = {0};
    for (int i = 0; i < g->n; i++) pieces_push(&P, g->a[i].f, g->a[i].len);
    for (;;) {
        int bo = 0, bi = -1, bj = -1;
        for (int i = 0; i < P.n; i++) {
            for (int j = 0; j < P.n; j++) {
                if (i == j) continue;
                int o = overlap(P.p[i].s, P.p[i].len, P.p[j].s, P.p[j].len);
                if (o <= 0) continue;
                if (o > bo || (o == bo && (bi < 0 || i < bi || (i == bi && j < bj)))) {
                    bo = o; bi = i; bj = j;
                }
            }
        }
        if (bo == 0) break;
        int nlen = P.p[bi].len + P.p[bj].len - bo;
        char *np = malloc(nlen + 1);
        memcpy(np, P.p[bi].s, P.p[bi].len);
        memcpy(np + P.p[bi].len, P.p[bj].s + bo, P.p[bj].len - bo);
        np[nlen] = 0;
        pieces_remove(&P, bi > bj ? bi : bj);
        pieces_remove(&P, bi > bj ? bj : bi);
        pieces_push(&P, np, nlen);
        free(np);
    }
    for (int i = 0; i < P.n; i++) pieces_push(out, P.p[i].s, P.p[i].len);
    pieces_free(&P);
}

/* Pack a chain into a Vec payload:
 *   [u32 chain_id][u32 nfrags] ( [u32 len][len bytes] )*nfrags */
static void pack_chain(Vec *v, unsigned cid, Frags *g) {
    pack_u32(v, cid);
    pack_u32(v, (unsigned)g->n);
    for (int i = 0; i < g->n; i++) {
        pack_u32(v, (unsigned)g->a[i].len);
        vec_append(v, g->a[i].f, (size_t)g->a[i].len);
    }
}

/* Assemble every chain packed in a payload buffer, write contigs to `out`. */
static void assemble_buffer(const unsigned char *buf, size_t len, FILE *out) {
    size_t pos = 0;
    while (pos + 8 <= len) {
        unsigned cid = unpack_u32(buf + pos); pos += 4;
        unsigned nf = unpack_u32(buf + pos); pos += 4;
        Frags g = {0};
        for (unsigned k = 0; k < nf && pos + 4 <= len; k++) {
            unsigned fl = unpack_u32(buf + pos); pos += 4;
            if (pos + fl > len) break;
            frags_push(&g, (const char *)(buf + pos), (int)fl);
            pos += fl;
        }
        Pieces outp = {0};
        assemble_frags(&g, &outp);
        for (int i = 0; i < outp.n; i++) {
            fwrite(outp.p[i].s, 1, outp.p[i].len, out);
            fputc('\n', out);
        }
        for (int i = 0; i < g.n; i++) free(g.a[i].f);
        free(g.a);
        pieces_free(&outp);
    }
}

int main(int argc, char **argv) {
    int rank, size;
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    if (argc < 3) {
        if (rank == 0) fprintf(stderr, "usage: mpi_sim <input.txt> <outdir>\n");
        MPI_Finalize();
        return 2;
    }
    const char *inpath = argv[1];
    const char *outdir = argv[2];

    /* rank 0 builds a per-rank payload vector, sends to others, assembles own. */
    Vec own = {0}; /* rank 0's own payload */

    if (rank == 0) {
        char cmd[4096];
        snprintf(cmd, sizeof(cmd), "mkdir -p %s", outdir);
        system(cmd);
        FILE *f = fopen(inpath, "r");
        if (!f) { fprintf(stderr, "cannot open %s\n", inpath); MPI_Abort(MPI_COMM_WORLD, 3); }
        char line[MAXLINE];
        Vec *vecs = calloc((size_t)size, sizeof(Vec));
        long cur_cid = -1;
        Frags cur = {0};
        long parsed = 0;
        while (fgets(line, sizeof(line), f)) {
            if (line[0] == '\n' || line[0] == '\0') continue;
            char *tab = strchr(line, '\t');
            if (!tab) { parsed++; continue; }
            *tab = 0;
            long cid = atol(line);
            char *fp = tab + 1;
            size_t fl = strlen(fp);
            if (fl && fp[fl - 1] == '\n') fp[--fl] = 0;
            if (cid != cur_cid) {
                if (cur_cid >= 0) {
                    unsigned c = (unsigned)((cur_cid % size + size) % size);
                    pack_chain(&vecs[c], (unsigned)cur_cid, &cur);
                }
                cur.n = 0; /* keep capacity, contents freed below */
                cur_cid = cid;
            }
            frags_push(&cur, fp, (int)fl);
            parsed++;
        }
        if (cur_cid >= 0) {
            unsigned c = (unsigned)((cur_cid % size + size) % size);
            pack_chain(&vecs[c], (unsigned)cur_cid, &cur);
        }
        for (int i = 0; i < cur.n; i++) free(cur.a[i].f);
        free(cur.a);
        fclose(f);

        /* rank 0 assembles its own share */
        own.b = vecs[0].b; own.len = vecs[0].len; own.cap = vecs[0].cap;
        char outpath[4096];
        snprintf(outpath, sizeof(outpath), "%s/contigs.rank0.txt", outdir);
        FILE *out = fopen(outpath, "w");
        if (out) {
            assemble_buffer(own.b, own.len, out);
            fclose(out);
        }
        /* send remaining payloads to their ranks */
        for (int r = 1; r < size; r++) {
            unsigned char *buf = vecs[r].b;
            size_t n = vecs[r].len;
            MPI_Send((void *)buf, (int)n, MPI_BYTE, r, 7, MPI_COMM_WORLD);
        }
        for (int r = 1; r < size; r++) free(vecs[r].b);
        free(vecs);
        free(own.b);
    } else {
        /* non-root: receive its payload, assemble, write rank file */
        MPI_Status st;
        MPI_Probe(0, 7, MPI_COMM_WORLD, &st);
        int n = 0;
        MPI_Get_count(&st, MPI_BYTE, &n);
        unsigned char *buf = n ? malloc((size_t)n) : NULL;
        MPI_Recv(buf, n, MPI_BYTE, 0, 7, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        char outpath[4096];
        snprintf(outpath, sizeof(outpath), "%s/contigs.rank%d.txt", outdir, rank);
        FILE *out = fopen(outpath, "w");
        if (out) {
            assemble_buffer(buf, (size_t)n, out);
            fclose(out);
        }
        if (buf) free(buf);
    }

    MPI_Finalize();
    return 0;
}

MPIC

# --- deliverable 2: python process-pool hashing service --------------------
cat > /app/serve.py <<'PYEOF'
#!/usr/bin/env python3
"""prism-bridge : distributed file-hashing service worker.

Modes:
  python3 /app/serve.py <input_dir> <manifest_path>
      Hash every top-level regular file in <input_dir> with
      PBKDF2-HMAC-SHA256 (salt = sha256(basename), 60000 iterations) using a
      ProcessPoolExecutor (real worker *processes*, not threads), write one
      '<basename>\\t<hexdigest>' line per file (sorted by basename) to
      <manifest_path>, and (re)create exactly three worker marker files in
      /app/markers: STARTED.marker, WORKERS.marker, COMPLETED.marker.

  python3 /app/serve.py --status
      Print the installed java and hadoop versions as two lines:
          java  <major.minor...>
          hadoop <release>
"""
import hashlib
import os
import shutil
import subprocess
import sys
import time

WORKERS = 4
ITERATIONS = 60000
MARKER_DIR = "/app/markers"


def pbkdf2_hex(path):
    with open(path, "rb") as fh:
        data = fh.read()
    salt = hashlib.sha256(os.path.basename(path).encode()).digest()
    return hashlib.pbkdf2_hmac("sha256", data, salt, ITERATIONS).hex()


def hash_job(path):
    return os.path.basename(path), pbkdf2_hex(path), os.getpid()


def write_manifest(items, manifest_path):
    lines = sorted((name + "\t" + hexd for name, hexd, _ in items))
    with open(manifest_path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


def write_markers(filenames, items, started):
    os.makedirs(MARKER_DIR, exist_ok=True)
    with open(os.path.join(MARKER_DIR, "STARTED.marker"), "w") as fh:
        fh.write("started %d\nfiles %d\n" % (started, len(filenames)))
    pids = sorted(set(pid for _, _, pid in items))
    with open(os.path.join(MARKER_DIR, "WORKERS.marker"), "w") as fh:
        for pid in pids:
            fh.write("worker %d\n" % pid)
    with open(os.path.join(MARKER_DIR, "COMPLETED.marker"), "w") as fh:
        fh.write("completed %d\nfiles %d\nhashes %d\n"
                 % (int(time.time()), len(filenames), len(items)))


### ---- status mode (java + hadoop versions) ----
def detect_java():
    j = shutil.which("java")
    if not j:
        return None, None
    real = os.path.realpath(j)
    java_home = os.path.dirname(os.path.dirname(real))
    out = subprocess.run(["java", "-version"], capture_output=True, text=True)
    version_line = (out.stderr or out.stdout).splitlines()[:1]
    return (java_home, version_line[0] if version_line else None)


def detect_hadoop(java_home):
    hbin = "/opt/hadoop/bin/hadoop"
    if not os.path.exists(hbin):
        return None
    env = dict(os.environ)
    if java_home:
        env["JAVA_HOME"] = java_home
    out = subprocess.run([hbin, "version"], capture_output=True, text=True, env=env)
    first = out.stdout.splitlines()[:1]
    return first[0] if first else None


def status_main():
    java_home, java_raw = detect_java()
    hadoop_raw = detect_hadoop(java_home)
    if not java_raw or not java_home:
        print("java <missing>")
    else:
        print("java " + _short(java_raw))
    if not hadoop_raw:
        print("hadoop <missing>")
    else:
        print("hadoop " + _short(hadoop_raw))
    if not java_raw or not hadoop_raw:
        sys.exit(1)
    return 0


def _short(s):
    # 'openjdk version "11.0.32" 2026-...' or 'Hadoop 3.3.6' -> clean token
    import re
    m = re.search(r'(\d+\.\d+(?:\.\d+)?)', s)
    return m.group(1) if m else s.strip()


def hashing_main(input_dir, manifest_path):
    files = sorted(
        f for f in os.listdir(input_dir)
        if os.path.isfile(os.path.join(input_dir, f))
    )
    paths = [os.path.join(input_dir, f) for f in files]
    started = int(time.time())
    if not paths:
        write_manifest([], manifest_path)
        write_markers(files, [], started)
        return 0
    import concurrent.futures
    with concurrent.futures.ProcessPoolExecutor(max_workers=WORKERS) as ex:
        items = list(ex.map(hash_job, paths))
    write_manifest(items, manifest_path)
    write_markers(files, items, started)
    return 0


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--status":
        return status_main()
    if len(sys.argv) == 3:
        return hashing_main(sys.argv[1], sys.argv[2])
    print("usage: %s <input_dir> <manifest_path>   |   %s --status" %
          (sys.argv[0], sys.argv[0]), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())

PYEOF
chmod +x /app/serve.py

# --- compile the MPI program ----------------------------------------------
mpicc -O2 /app/mpi_main.c -o /app/mpi_sim

# --- install pinned hadoop + matching java 11 ------------------------------
export DEBIAN_FRONTEND=noninteractive
mkdir -p /opt

# java 11 via apt, with retries (apt is the only remaining network step).
inst_java() {
    apt-get update -qq >/tmp/aptup.log 2>&1 && \
        apt-get install -y -qq openjdk-11-jre-headless >/tmp/j.log 2>&1
}
for i in 1 2 3 4 5; do
    if inst_java; then break; fi
    sleep 10
    if [ "$i" = "5" ]; then tail -20 /tmp/aptup.log; tail -20 /tmp/j.log; fi
done
command -v java >/dev/null 2>&1 || { echo "ERROR: java 11 install failed"; exit 1; }

# hadoop 3.3.6: extract from the pre-staged tarball (deterministic, no
# network); fall back to the upstream fetch only if the stage is absent.
if [ -s /opt/hadoop-3.3.6.tar.gz ]; then
    if [ -f /opt/hadoop-3.3.6.tar.gz.sha512 ]; then
        expected=$(grep -oE '[0-9a-f]{128}' /opt/hadoop-3.3.6.tar.gz.sha512 | head -1)
        actual=$(sha512sum /opt/hadoop-3.3.6.tar.gz | awk '{print $1}')
        if [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
            echo "ERROR: pre-staged hadoop tarball failed sha512 check"; exit 1
        fi
    fi
    tar -xzf /opt/hadoop-3.3.6.tar.gz -C /opt
else
    curl -fsSL --retry 10 --retry-delay 5 --connect-timeout 30 \
        -o /tmp/hadoop.tgz \
        https://dlcdn.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz \
      || curl -fsSL --retry 10 --retry-delay 5 --connect-timeout 30 \
        -o /tmp/hadoop.tgz \
        https://archive.apache.org/dist/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz
    tar -xzf /tmp/hadoop.tgz -C /opt
    rm -f /tmp/hadoop.tgz
fi
[ -d /opt/hadoop-3.3.6 ] && ln -sfn /opt/hadoop-3.3.6 /opt/hadoop

# --- run service on the visible sample -> manifest + markers ----------------
python3 /app/serve.py /app/sample/files /app/manifest.txt

# --- self-check (never reads /tests) ---------------------------------------
python3 - <<'PYC'
import hashlib, os, subprocess, sys, concurrent.futures

def pb(rel):
    with open(rel,'rb') as fh: data=fh.read()
    salt=hashlib.sha256(os.path.basename(rel).encode()).digest()
    return os.path.basename(rel), hashlib.pbkdf2_hmac('sha256',data,salt,60000).hex()

# 1) serve.py manifest correctness on the visible sample
files=sorted(f for f in os.listdir('/app/sample/files') if os.path.isfile('/app/sample/files/'+f))
exp=[pb('/app/sample/files/'+f) for f in files]
exp_lines=sorted(n+'\t'+h for n,h in exp)
got=open('/app/manifest.txt').read().splitlines()
assert got==exp_lines, (got, exp_lines)

# 2) markers: exactly three, and at least 2 distinct worker PIDs
want={'STARTED.marker','WORKERS.marker','COMPLETED.marker'}
mdir=os.listdir('/app/markers')
assert set(mdir)==want, mdir
pids=[]
for ln in open('/app/markers/WORKERS.marker'):
    pids.append(int(ln.split()[1]))
assert len(set(pids))>=2, pids

# 3) MPI: serial == parallel on the visible sample
subprocess.run(['mkdir','-p','/app/self/ser','/app/self/par'],check=True)
subprocess.run(['mpirun','--allow-run-as-root','--oversubscribe','-np','1',
                '/app/mpi_sim','/app/sample/reads.mpi.txt','/app/self/ser'],check=True)
subprocess.run(['mpirun','--allow-run-as-root','--oversubscribe','-np','4',
                '/app/mpi_sim','/app/sample/reads.mpi.txt','/app/self/par'],check=True)
def contigs(d):
    out=[]
    for r in os.listdir(d):
        out+=open(os.path.join(d,r)).read().splitlines()
    return sorted(out)
ser=contigs('/app/self/ser'); par=contigs('/app/self/par')
assert ser==par, (ser,par)
print('oracle self-check OK')
PYC

# --- report status ----------------------------------------------------------
python3 /app/serve.py --status
echo "PRISM-BRIDGE ORACLE DONE"
