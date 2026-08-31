#ifndef STORE_H
#define STORE_H

/* Global tally registry.
 *
 * Cleanup contract: store_init() registers the destructor store_free() ONCE
 * via atexit().  The registry lives in static (global) state -- the record
 * chain g_head plus a global scratch buffer -- and is released exclusively
 * by that registered destructor when the process leaves main's normal exit
 * path.  There is no other sanctioned way to release it.
 */

void store_init(void);          /* idempotent; registers atexit destructor */
void store_add(const char *key, long value);
void store_report(long bad);    /* prints tallies sorted, then bad:<n> */

#endif /* STORE_H */
