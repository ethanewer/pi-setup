/*
 * keeper.c — hidden gate build (verification fixture: gate-one).
 */
#include <stdio.h>
#include <string.h>

#define TAG_LEN 40
#define PERMIT_MAGIC 0x00C0FFEEu

struct session {
    char tag[TAG_LEN];
    unsigned int permit;
};

int main(void) {
    struct session s;
    memset(&s, 0, sizeof(s));
    fread(s.tag, 1, TAG_LEN + sizeof(unsigned int), stdin);
    if (s.permit == PERMIT_MAGIC) {
        printf("KEEPER_OPEN code=RZ-1108\n");
    } else {
        printf("LOCKED\n");
    }
    return 0;
}
