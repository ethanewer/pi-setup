#!/usr/bin/env python3
"""Apply the capstan-pilot fix to a pristine git 2.46-era builtin/notes.c.

Root cause: the notes add/append paths decide whether to invoke the editor in
prepare_note_data() by checking the note_data.given flag, which add() and
append_edit() set to ``!!d.buf.len`` -- i.e. "non-empty accumulated message
buffer". When the user supplies the note contents on the command line via
-m/-F/-c/-C but the contents are empty, the accumulated buffer has length 0,
so given == 0 and the editor is launched even though the caller supplied the
contents (this regressed in 90bc19b3ae, 2023-05).

The fix (matching upstream commit 8b426c8) is to decide on ``d.msg_nr``
(whether any -m/-F/-c/-C callback ran at all) instead of the buffer length:
- prepare_note_data(): use !d->msg_nr for both the editor decision and the
  buffer-copy decision,
- remove the now-unneeded `given` field from struct note_data,
- add(): drop the `d.given = !!d.buf.len;` line and use d.msg_nr for the
  existing-note error branch,
- append_edit(): drop the given flag, guard the deprecation warning (which is
  only printed when messages were actually supplied) with d.msg_nr.

Run:  python3 fix_notes.py   (from anywhere; edits /app/src by default)
"""
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/app/src"
PATH = f"{ROOT}/builtin/notes.c"


def edit(path, old, new, count=1):
    with open(path) as f:
        s = f.read()
    n = s.count(old)
    if n < count:
        sys.exit(f"ERROR: anchor not found in {path} (wanted {count}, found {n}):\n---\n{old}\n---")
    s = s.replace(old, new, count)
    with open(path, "w") as f:
        f.write(s)


# 1. drop the `given` field from struct note_data
edit(PATH,
     "\tint given;\n\tint use_editor;\n",
     "\tint use_editor;\n")

# 2. prepare_note_data(): editor decision on msg_nr, not buffer length
edit(PATH,
     "\tif (d->use_editor || !d->given) {",
     "\tif (d->use_editor || !d->msg_nr) {")
edit(PATH,
     "\t\tif (d->given)\n\t\t\twrite_or_die(fd, d->buf.buf, d->buf.len);",
     "\t\tif (d->msg_nr)\n\t\t\twrite_or_die(fd, d->buf.buf, d->buf.len);")

# 3. add(): remove the given-flag assignment (anchor is unique to add():
#    append_edit resolves with `1 < argc ? argv[1] : "HEAD"` instead)
edit(PATH,
     "\tif (d.msg_nr)\n\t\tconcat_messages(&d);\n\td.given = !!d.buf.len;\n\n"
     "\tobject_ref = argc > 1 ? argv[1] : \"HEAD\";",
     "\tif (d.msg_nr)\n\t\tconcat_messages(&d);\n\n"
     "\tobject_ref = argc > 1 ? argv[1] : \"HEAD\";")
edit(PATH,
     "\t\t\tfree_notes(t);\n\t\t\tif (d.given) {\n\t\t\t\tfree_note_data(&d);",
     "\t\t\tfree_notes(t);\n\t\t\tif (d.msg_nr) {\n\t\t\t\tfree_note_data(&d);")

# 4. append_edit(): remove the given flag, guard the deprecation warning with
#    d.msg_nr, restoring the restructured upstream form
edit(PATH,
     "\tif (d.msg_nr)\n\t\tconcat_messages(&d);\n\td.given = !!d.buf.len;\n\n"
     "\tif (d.given && edit)\n"
     "\t\tfprintf(stderr, _(\"The -m/-F/-c/-C options have been deprecated \"\n"
     "\t\t\t\"for the 'edit' subcommand.\\n\"\n"
     "\t\t\t\"Please use 'git notes add -f -m/-F/-c/-C' instead.\\n\"));",
     "\tif (d.msg_nr) {\n"
     "\t\tconcat_messages(&d);\n"
     "\t\tif (edit)\n"
     "\t\t\tfprintf(stderr, _(\"The -m/-F/-c/-C options have been \"\n"
     "\t\t\t\t\"deprecated for the 'edit' subcommand.\\n\"\n"
     "\t\t\t\t\"Please use 'git notes add -f -m/-F/-c/-C' \"\n"
     "\t\t\t\t\"instead.\\n\"));\n"
     "\t}")

# sanity: the flag must be gone entirely
with open(PATH) as f:
    leftover = f.read().count("d.given") + f.read().count("d->given")
if leftover:
    sys.exit(f"ERROR: {leftover} 'given' references left in {PATH}")
print("fix_notes.py: builtin/notes.c patched (editor decision now keyed on msg_nr)")