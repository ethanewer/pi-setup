/* Meridian-7 rendezvous client (reference implementation).
 * Talk to the rendezvous server: HELLO -> ACK(nonce), AUTH -> AUTHOK, FLOWS -> records.
 * Frame: [1-byte opcode][2-byte big-endian length][payload].
 *  0x11 HELLO (payload: 4-byte magic 0x1357BEEF)   -> 0x21 ACK (8-byte server nonce)
 *  0x12 AUTH (payload: 32-char hex = sha256(secret+nonce).hexdigest()[:32])
 *                                                 -> 0x22 AUTHOK (4-byte big-endian flow count)
 *                                                    | 0x23 AUTHFAIL
 *  0x13 FLOWS (empty payload)                      -> 0x24 (concat of 2-byte len + flow line)
 * Flow line: "SRCIP,DSTIP,SRCPORT,DSTPORT,PROTO,PKTS,OCTETS"
 * Usage: client <host> <port>
 * Compile: gcc client.c -o client -lssl -lcrypto
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <openssl/sha.h>

#define SECRET "MERIDIANKEY-7f3c"
#define MAGIC  0x1357BEEF

static int connect_to(const char *host, int port) {
    struct hostent *he = gethostbyname(host);
    if (!he) { perror("gethostbyname"); return -1; }
    int s = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons((unsigned short)port);
    memcpy(&a.sin_addr, he->h_addr_list[0], (size_t)he->h_length);
    if (connect(s, (struct sockaddr*)&a, sizeof(a)) != 0) { perror("connect"); return -1; }
    return s;
}
static void send_frame(int s, unsigned char op, const unsigned char *p, int n) {
    unsigned char h[3] = { op, (unsigned char)((n >> 8) & 0xff), (unsigned char)(n & 0xff) };
    (void)!write(s, h, 3);
    if (n) (void)!write(s, p, (size_t)n);
}
static int recv_frame(int s, unsigned char *op, unsigned char **payload, int *plen) {
    unsigned char h[3];
    int got = 0;
    while (got < 3) { int r = (int)read(s, h + got, 3 - got); if (r <= 0) return -1; got += r; }
    *op = h[0];
    *plen = ((int)h[1] << 8) | h[2];
    *payload = NULL;
    if (*plen > 0) {
        *payload = malloc((size_t)*plen);
        got = 0;
        while (got < *plen) { int r = (int)read(s, (*payload) + got, (size_t)(*plen - got)); if (r <= 0) return -1; got += r; }
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: client <host> <port>\n"); return 2; }
    int s = connect_to(argv[1], atoi(argv[2]));
    if (s < 0) return 2;

    unsigned char magic[4] = { 0x13, 0x57, 0xBE, 0xEF };
    send_frame(s, 0x11, magic, 4);
    unsigned char op; unsigned char *payload = NULL; int plen = 0;
    if (recv_frame(s, &op, &payload, &plen) != 0 || op != 0x21 || plen != 8) {
        fprintf(stderr, "bad handshake\n"); return 3;
    }
    /* nonce in payload */
    unsigned char buf[4096];
    size_t sl = strlen(SECRET);
    memcpy(buf, SECRET, sl);
    memcpy(buf + sl, payload, 8);
    unsigned char md[SHA256_DIGEST_LENGTH];
    SHA256(buf, sl + 8, md);
    char hex[65];
    for (int i = 0; i < 16; i++) sprintf(hex + 2 * i, "%02x", md[i]);
    hex[32] = 0;
    free(payload);

    send_frame(s, 0x12, (unsigned char*)hex, 32);
    if (recv_frame(s, &op, &payload, &plen) != 0 || op != 0x22) {
        fprintf(stderr, "auth failed\n"); return 4;
    }
    int nflows = ((int)payload[0] << 24) | ((int)payload[1] << 16) | ((int)payload[2] << 8) | payload[3];
    free(payload);

    send_frame(s, 0x13, NULL, 0);
    if (recv_frame(s, &op, &payload, &plen) != 0 || op != 0x24) {
        fprintf(stderr, "flows failed\n"); return 5;
    }
    int o = 0;
    while (o + 2 <= plen) {
        int l = ((int)payload[o] << 8) | payload[o + 1];
        o += 2;
        if (o + l > plen) break;
        /* write the flow line then the count */
        if (nflows >= 0) { /* placeholder */ }
        o += l;
    }
    free(payload);
    close(s);
    return 0;
}
