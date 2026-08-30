/*
 * main.c — protected driver for the forge bench. DO NOT MODIFY.
 *
 * Drives the pool allocator in forge.c with a workload file:
 *   A <id> <n>   allocate n bytes and bind them to <id> (if <id> was already
 *                live, its old block is released first)
 *   W <id> <v>   fill every byte of the live block <id> with the byte v
 *                (0..255); v is recorded as the block's fill value
 *   F <id>       release the live block <id>
 * Anything else (unknown opcodes, malformed lines, blank lines) is ignored
 * harmlessly.
 *
 * The driver honours the allocator contract and writes into every block it
 * receives unconditionally. At the end it prints exactly one line:
 *   FORGE-OK <checksum>
 * where <checksum> is the sum, over all live blocks, of
 *   (recorded byte size) * (fill value + 1), computed modulo 2^64.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *forge_alloc(size_t n);
void forge_free(void *p);

#define MAX_SLOTS 4096
#define ID_LEN 64

typedef struct {
    char id[ID_LEN];
    unsigned char *p;
    size_t size;
    unsigned char fill;
    int live;
} Slot;

static Slot slots[MAX_SLOTS];

static Slot *find_slot(const char *id)
{
    for (int i = 0; i < MAX_SLOTS; i++)
        if (slots[i].live && strcmp(slots[i].id, id) == 0)
            return &slots[i];
    return NULL;
}

static Slot *claim_slot(const char *id)
{
    for (int i = 0; i < MAX_SLOTS; i++)
        if (!slots[i].live && slots[i].id[0] == '\0') {
            snprintf(slots[i].id, ID_LEN, "%s", id);
            return &slots[i];
        }
    return NULL;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: forgebench <workload-file>\n");
        return 2;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("workload");
        return 2;
    }

    char line[512];
    while (fgets(line, sizeof line, f)) {
        char a[ID_LEN], b[ID_LEN], c[ID_LEN];
        int nt = sscanf(line, "%63s %63s %63s", a, b, c);
        if (nt <= 0)
            continue;
        if (strcmp(a, "A") == 0 && nt >= 3) {
            char *end = NULL;
            long n = strtol(c, &end, 10);
            if (*c == '\0' || end == c || n < 0)
                continue;
            Slot *s = find_slot(b);
            if (s) { /* re-allocation of a live id: release the old block */
                forge_free(s->p);
                s->live = 0;
                s->id[0] = '\0';
            }
            s = claim_slot(b);
            if (!s)
                continue;
            s->p = forge_alloc((size_t)n);
            s->size = (size_t)n;
            s->fill = 0;
            s->live = 1;
        } else if (strcmp(a, "W") == 0 && nt >= 3) {
            char *end = NULL;
            long v = strtol(c, &end, 10);
            if (*c == '\0' || end == c || v < 0)
                continue;
            Slot *s = find_slot(b);
            if (s) {
                memset(s->p, (int)(v & 0xff), s->size);
                s->fill = (unsigned char)(v & 0xff);
            }
        } else if (strcmp(a, "F") == 0 && nt >= 2) {
            Slot *s = find_slot(b);
            if (s) {
                forge_free(s->p);
                s->live = 0;
                s->id[0] = '\0';
            }
        }
    }
    fclose(f);

    unsigned long long sum = 0;
    for (int i = 0; i < MAX_SLOTS; i++)
        if (slots[i].live)
            sum += (unsigned long long)slots[i].size *
                   (unsigned long long)(slots[i].fill + 1ULL);
    printf("FORGE-OK %llu\n", sum);
    return 0;
}
