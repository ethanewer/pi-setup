#!/usr/bin/env python3
"""Apply the root-cause fix to the working redis tree.

The defect: in src/t_stream.c, xsetidCommand() sets s->entries_added directly
from the ENTRIESADDED option. When that lowers the counter below what one of
the stream's consumer groups has already read, the group's entries_read is
left above entries_added, which makes XINFO GROUPS report a negative lag and
which produces RDB payloads whose cgroup entries_read is inconsistent with
entries_added, so the loader refuses them (DEBUG RELOAD / restart / replica
full-sync fail).

The fix: when ENTRIESADDED lowers entries_added below its previous value,
clamp every consumer group's entries_read down to the new entries_added,
skipping groups whose read position is unset (SCG_INVALID_ENTRIES_READ) --
exactly the rule XGROUP CREATE/SETID already apply.
"""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else '/app/src/src/t_stream.c'
with open(path, encoding='utf-8') as fh:
    src = fh.read()

anchor = """    s->last_id = id;
    if (entries_added != -1)
        s->entries_added = entries_added;"""
assert src.count(anchor) == 1, 'anchor not found or not unique in %s' % path

replacement = """    s->last_id = id;
    if (entries_added != -1) {
        uint64_t prev_entries_added = s->entries_added;
        s->entries_added = entries_added;

        /* Lowering entries_added can leave a consumer group's entries_read
         * greater than the stream's entries_added. That breaks the lag
         * calculation (XINFO GROUPS would report a negative lag) and
         * produces RDB payloads the loader rejects. Clamp each group's read
         * position down to the new counter, the same rule XGROUP
         * CREATE/SETID already enforce. */
        if (s->entries_added < prev_entries_added && s->cgroups) {
            raxIterator ri;
            raxStart(&ri, s->cgroups);
            raxSeek(&ri, "^", NULL, 0);
            while (raxNext(&ri)) {
                streamCG *cg = ri.data;
                if (cg->entries_read != SCG_INVALID_ENTRIES_READ &&
                    (uint64_t)cg->entries_read > s->entries_added)
                {
                    cg->entries_read = s->entries_added;
                }
            }
            raxStop(&ri);
        }
    }"""

src = src.replace(anchor, replacement)

with open(path, 'w', encoding='utf-8') as fh:
    fh.write(src)

print('fixed: xsetidCommand now clamps consumer-group entries_read when '
      'ENTRIESADDED lowers the stream counter')