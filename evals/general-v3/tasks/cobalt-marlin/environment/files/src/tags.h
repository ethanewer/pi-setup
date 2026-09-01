#ifndef TAGS_H
#define TAGS_H

/*
 * tags - validation helpers for the batchstat metric tool (provided, correct).
 *
 * A valid TAG is [a-z][a-z0-9_]* : the first character must be a lowercase
 * letter, the rest may be lowercase letters, digits, or underscore.
 * A valid VALUE is an optionally-signed decimal integer: exactly one optional
 * '-' followed by one or more decimal digits, and nothing else.
 */

/* Returns 1 if tag is a valid TAG (non-NULL, valid charset), else 0. */
int tag_valid(const char *tag);

/* Returns 1 and stores the parsed value in *out if s is a valid VALUE,
 * else returns 0 (and leaves *out untouched). */
int parse_long(const char *s, long *out);

#endif /* TAGS_H */
