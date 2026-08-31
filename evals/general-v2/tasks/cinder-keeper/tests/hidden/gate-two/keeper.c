/*
 * keeper.c — hidden gate build (verification fixture: gate-two).
 */
#include <stdio.h>
#include <string.h>

#define TAG_LEN 12
#define PERMIT_MAGIC 4000000000

struct session {
    char tag[TAG_LEN];
    unsigned int permit;
};

int main(void) {
    struct session s;
    memset(&s, 0, sizeof(s));
    fread(s.tag, 1, TAG_LEN + sizeof(unsigned int), stdin);
    if (s.permit == PERMIT_MAGIC) {
        printf("KEEPER_OPEN code=WP-7205\n");
    } else {
        printf("LOCKED\n");
    }
    return 0;
}
