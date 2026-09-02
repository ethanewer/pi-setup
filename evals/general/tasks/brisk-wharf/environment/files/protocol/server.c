/* Meridian-7 telemetry rendezvous server.
 * Custom binary protocol. Frame: [1-byte opcode][2-byte big-endian len][payload].
 * 0x11 HELLO (payload: 4-byte magic 0x1357BEEF)      -> 0x21 ACK (8-byte server nonce)
 * 0x12 AUTH (payload: 32-byte hex = sha256(SECRET+nonce)[:32]) -> 0x22 AUTHOK (4-byte flow count) | 0x23 AUTHFAIL
 * 0x13 FLOWS (empty)                                 -> 0x24 (length-prefixed flow lines)
 * Usage: server <port> <flows_file>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <openssl/sha.h>

#define SECRET "MERIDIANKEY-7f3c"
#define MAGIC  0x1357BEEF

static void send_frame(int fd, unsigned char op, const unsigned char *payload, int plen) {
    unsigned char hdr[3] = { op, (unsigned char)((plen >> 8) & 0xff), (unsigned char)(plen & 0xff) };
    (void)!write(fd, hdr, 3);
    if (plen > 0) (void)!write(fd, payload, (size_t)plen);
}
static int recv_exact(int fd, unsigned char *buf, int n) {
    int got = 0;
    while (got < n) {
        int r = (int)read(fd, buf + got, (size_t)(n - got));
        if (r <= 0) return -1;
        got += r;
    }
    return 0;
}
/* returns 1 if a frame is available (blocking), fills op & payload(allocated) */
static int recv_frame(int fd, unsigned char *op, unsigned char **payload, int *plen) {
    unsigned char hdr[3];
    if (recv_exact(fd, hdr, 3) != 0) return -1;
    *op = hdr[0];
    *plen = ((int)hdr[1] << 8) | hdr[2];
    *payload = NULL;
    if (*plen > 0) {
        *payload = malloc((size_t)*plen);
        if (recv_exact(fd, *payload, *plen) != 0) { free(*payload); return -1; }
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: server <port> <flows_file>\n"); return 2; }
    int port = atoi(argv[1]);
    /* load flow lines */
    FILE *ff = fopen(argv[2], "r");
    if (!ff) { fprintf(stderr, "cannot open %s\n", argv[2]); return 2; }
    char line[4096];
    char *flows[512]; int nflows = 0;
    while (nflows < 512 && fgets(line, sizeof(line), ff)) {
        if (line[0] == '\n' || line[0] == '\0') continue;
        size_t l = strlen(line);
        if (l && line[l-1] == '\n') line[--l] = 0;
        if (l) flows[nflows++] = strdup(line);
    }
    fclose(ff);

    int ls = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1; setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons((unsigned short)port);
    if (bind(ls, (struct sockaddr*)&addr, sizeof(addr)) != 0) { perror("bind"); return 2; }
    if (listen(ls, 16) != 0) { perror("listen"); return 2; }

    srand((unsigned)time(NULL) ^ (unsigned)getpid());
    for (;;) {
        int c = accept(ls, NULL, NULL);
        if (c < 0) continue;
        /* per-connection nonce */
        unsigned long long nonce = ((unsigned long long)rand() << 32) ^ (unsigned long long)rand();
        unsigned char nonceb[8];
        for (int i = 0; i < 8; i++) nonceb[i] = (unsigned char)(nonce >> (8 * (7 - i)));
        int authed = 0;
        for (;;) {
            unsigned char op; unsigned char *payload = NULL; int plen = 0;
            if (recv_frame(c, &op, &payload, &plen) != 1) break;
            if (op == 0x11) {
                int magic_ok = (plen == 4);
                if (magic_ok && payload) {
                    unsigned int mval = ((unsigned)payload[0]<<24)|((unsigned)payload[1]<<16)|((unsigned)payload[2]<<8)|payload[3];
                    if (mval != MAGIC) magic_ok = 0;
                }
                if (!magic_ok) { send_frame(c, 0x23, (unsigned char*)"BADMAGIC", 8); free(payload); break; }
                send_frame(c, 0x21, nonceb, 8);
            } else if (op == 0x12) {
                /* compute expected MAC: hex of sha256(SECRET||nonce)[:16] */
                unsigned char buf[4096];
                size_t sl = strlen(SECRET);
                memcpy(buf, SECRET, sl);
                memcpy(buf + sl, nonceb, 8);
                unsigned char md[SHA256_DIGEST_LENGTH];
                SHA256(buf, sl + 8, md);
                char hex[65];
                for (int i = 0; i < 16; i++) sprintf(hex + 2*i, "%02x", md[i]);
                hex[32] = 0;
                if (plen == 32 && payload && strncmp((char*)payload, hex, 32) == 0) {
                    authed = 1;
                    unsigned char cnt[4] = {
                        (unsigned char)((nflows >> 24) & 0xff), (unsigned char)((nflows >> 16) & 0xff),
                        (unsigned char)((nflows >> 8) & 0xff), (unsigned char)(nflows & 0xff) };
                    send_frame(c, 0x22, cnt, 4);
                } else {
                    send_frame(c, 0x23, (unsigned char*)"AUTHFAIL", 8);
                }
            } else if (op == 0x13) {
                if (!authed) { send_frame(c, 0x23, (unsigned char*)"AUTHFAIL", 8); break; }
                /* build payload: each flow length-prefixed */
                int tot = 0;
                for (int i = 0; i < nflows; i++) tot += 2 + (int)strlen(flows[i]);
                unsigned char *pload = calloc(1, (size_t)(tot + 4096));
                int o = 0;
                for (int i = 0; i < nflows; i++) {
                    int l = (int)strlen(flows[i]);
                    pload[o++] = (unsigned char)((l >> 8) & 0xff);
                    pload[o++] = (unsigned char)(l & 0xff);
                    memcpy(pload + o, flows[i], (size_t)l); o += l;
                }
                send_frame(c, 0x24, pload, o);
                free(pload);
                free(payload);
                close(c);
                goto next;
            }
            if (payload) free(payload);
        }
        close(c);
        next:;
    }
    return 0;
}
