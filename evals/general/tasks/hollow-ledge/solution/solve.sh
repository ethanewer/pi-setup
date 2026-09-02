#!/bin/bash
# Hollow Ledge oracle. Performs the REAL recovery: writes decode.c (the
# deliverable program), compiles it, and USES IT to decode the WAL, carve the
# embedded key/cert, reverse the password check, and assemble deliverables.
# Never reads /tests; only touches /app paths.
set -eu

# ---------------------------------------------------------------------------
# 1) Write and compile the deliverable recovery program /app/decode.c
# ---------------------------------------------------------------------------
cat > /app/decode.c <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static unsigned char *readall(const char *path, long *outn) {
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); return NULL; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *b = malloc(n > 0 ? (size_t)n : 1);
    if (!b) { fclose(f); return NULL; }
    if (fread(b, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(b); return NULL; }
    fclose(f);
    *outn = n;
    return b;
}

static int writeall(const char *path, const unsigned char *b, long n) {
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    size_t w = fwrite(b, 1, (size_t)n, f);
    fclose(f);
    return (w == (size_t)n) ? 0 : -1;
}

static long findmark(const unsigned char *b, long n,
                     const unsigned char *m, int ml, long from) {
    for (long i = from; i + ml <= n; i++) {
        int ok = 1;
        for (int j = 0; j < ml; j++) if (b[i + j] != m[j]) { ok = 0; break; }
        if (ok) return i;
    }
    return -1;
}

static long rd_u32le(const unsigned char *p) {
    return (long)p[0] | ((long)p[1] << 8) | ((long)p[2] << 16) | ((long)p[3] << 24);
}

/* unwal <obf> <out> : find single-byte XOR key by WAL magic, decode, write. */
static int do_unwal(const char *in, const char *out) {
    long n;
    unsigned char *buf = readall(in, &n);
    if (!buf) return 1;
    static const unsigned char magic[4] = { 0x37, 0x7f, 0x06, 0x82 };
    int key = -1, k;
    for (k = 0; k < 256 && key < 0; k++) {
        int ok = 1;
        for (int i = 0; i < 4; i++) if ((buf[i] ^ (unsigned char)k) != magic[i]) { ok = 0; break; }
        if (ok) key = k;
    }
    if (key < 0) { fprintf(stderr, "no WAL magic found\n"); free(buf); return 2; }
    for (long i = 0; i < n; i++) buf[i] ^= (unsigned char)key;
    if (writeall(out, buf, n) != 0) { free(buf); return 3; }
    printf("KEY=%d\n", key);
    free(buf);
    return 0;
}

/* carve <carrier> <outdir> : recover the two length-prefixed PEM blobs. */
static int do_carve(const char *carrier, const char *outdir) {
    long n;
    unsigned char *buf = readall(carrier, &n);
    if (!buf) return 1;
    static const unsigned char MA[4] = { 'L','V','P','R' };
    static const unsigned char MB[4] = { 'L','V','C','R' };
    long i = findmark(buf, n, MA, 4, 0);
    if (i < 0) { fprintf(stderr, "no LVPR marker\n"); free(buf); return 2; }
    long priv_start = i + 4;
    long priv_len  = rd_u32le(buf + priv_start);
    long priv = priv_start + 4;
    if (priv + priv_len > n) { fprintf(stderr, "priv len overflow\n"); free(buf); return 3; }
    long j = findmark(buf, n, MB, 4, priv + priv_len);
    if (j < 0) { fprintf(stderr, "no LVCR marker\n"); free(buf); return 4; }
    long cert_l = j + 4;
    long cert_len = rd_u32le(buf + cert_l);
    long cert = cert_l + 4;
    if (cert + cert_len > n) { fprintf(stderr, "cert len overflow\n"); free(buf); return 5; }

    struct stat st;
    if (stat(outdir, &st) != 0) mkdir(outdir, 0755);
    char pp[4096], cp[4096];
    snprintf(pp, sizeof pp, "%s/privkey.pem", outdir);
    snprintf(cp, sizeof cp, "%s/cert.pem", outdir);
    int r1 = writeall(pp, buf + priv, priv_len);
    int r2 = writeall(cp, buf + cert, cert_len);
    free(buf);
    if (r1 || r2) return 6;
    printf("privkey=%ld bytes cert=%ld bytes\n", priv_len, cert_len);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: decode unwal <obf> <out> | carve <carrier> <outdir>\n");
        return 2;
    }
    if (strcmp(argv[1], "unwal") == 0 && argc >= 4) return do_unwal(argv[2], argv[3]);
    if (strcmp(argv[1], "carve") == 0 && argc >= 4) return do_carve(argv[2], argv[3]);
    fprintf(stderr, "bad subcommand\n");
    return 2;
}
C

gcc -O2 -o /app/decode /app/decode.c

# ---------------------------------------------------------------------------
# 2) USE the program: recover the valid WAL, then the cfg rows.
# ---------------------------------------------------------------------------
/app/decode unwal /app/ledge.db-wal.obf /app/ledge.db-wal

# ---------------------------------------------------------------------------
# 3) USE the program: carve the embedded key + cert.
# ---------------------------------------------------------------------------
rm -rf /app/recovered
/app/decode carve /app/carrier.bin /app/recovered

# ---------------------------------------------------------------------------
# 4) Read the restored cfg, reverse the check, assemble key.pem + creds.txt
# ---------------------------------------------------------------------------
python3 - <<'PY'
import sqlite3

# Recover username / passhash / salt / endpoint from the restored WAL.
con = sqlite3.connect('/app/ledge.db')
cfg = {k: v for k, v in con.execute("SELECT key, value FROM cfg")}
user    = cfg['username'].decode()
passhash = cfg['passhash']
endpoint = cfg['endpoint'].decode()
salt     = cfg['salt']
con.close()

# Reverse f(x) = ((x*0x35 + 0x2f) ^ 0xa5) & 0xff using its mod-256 inverse.
INV35 = pow(0x35, -1, 256)          # 109
def finv(y):
    return (((y ^ 0xa5) - 0x2f) & 0xff) * INV35 & 0xff
secret = bytes(finv(y) for y in passhash).decode('ascii')
assert len(secret) == 12 and all(0x20 <= ord(c) <= 0x7e for c in secret)

# Sanity: the pre-built validator must ACCEPT the recovered secret.
import subprocess
r = subprocess.run(['/usr/local/bin/ledgecheck', secret], capture_output=True, text=True)
assert r.returncode == 0 and r.stdout.strip() == 'ACCEPT', r.stdout

# Part 4: combined key-and-certificate PEM = privkey bytes then cert bytes.
priv = open('/app/recovered/privkey.pem', 'rb').read()
cert = open('/app/recovered/cert.pem', 'rb').read()
open('/app/key.pem', 'wb').write(priv + cert)

# Part 5: credentials text file.
with open('/app/creds.txt', 'w') as f:
    f.write("username=%s\n" % user)
    f.write("password=%s\n" % secret)

print("user=%s secret=%s" % (user, secret))
print("carved priv=%d cert=%d" % (len(priv), len(cert)))
PY

# Final cross-check output files are present and consistent.
# Re-restore the valid WAL last (sqlite merges and deletes the -wal on the
# triggered connection close) so the deliverable /app/ward.db-wal still exists.
/app/decode unwal /app/ledge.db-wal.obf /app/ledge.db-wal
[ -f /app/ledge.db-wal ] && [ -f /app/recovered/privkey.pem ] && \
  [ -f /app/recovered/cert.pem ] && [ -f /app/key.pem ] && [ -f /app/creds.txt ]
echo "hollow-ledge oracle finished"