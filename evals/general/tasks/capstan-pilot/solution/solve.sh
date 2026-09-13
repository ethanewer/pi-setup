#!/bin/bash
# Oracle for capstan-pilot: repair builtin/notes.c in the real upstream tree,
# write the diagnosis deliverable, rebuild with the project's own make, and
# self-check the fix with a direct repro. No verifier-path references here.
set -u
cd /app/src || { echo "no /app/src"; exit 1; }

python3 /solution/fix_notes.py || { echo "fix_notes.py failed"; exit 1; }

mkdir -p /app
cat > /app/diagnosis.md <<'EOF'
# Root cause: empty note contents supplied via -m/-F/-c/-C still launch the editor

The defect is in builtin/notes.c, in the notes add/append code path.

prepare_note_data() decides whether to launch the editor by testing the
note_data.given flag: `if (d->use_editor || !d->given)`. That flag is set at
the end of add() (and append_edit()) as `d.given = !!d.buf.len`, i.e. it is
derived from the LENGTH of the accumulated message buffer after concat_messages().
When the user supplies the note contents on the command line via -m/-F/-c/-C
but those contents are empty - `-C <empty-blob>`, `-m ""` or `-F /dev/null` -
concat_messages() produces a zero-length buffer, so given is 0 and
prepare_note_data() takes the editor branch even though the caller did supply
the contents. The editor then runs (and fails in a non-interactive
environment: "error: there was a problem with the editor ..."), and because
the template was never filled in, git dies with
"fatal: please supply the note contents using either -m or -F option", exit
code 128, storing nothing. This regressed when the editor decision was
switched to a zero-length-buffer check (regression introduced upstream in
2023; commit 90bc19b3ae).

The fix restores the pre-regression behaviour: decide on whether any
-m/-F/-c/-C parameter callback ran at all, not on the buffer length. The
note_data struct already counts supplied messages in msg_nr, so:

- prepare_note_data() now checks `d->use_editor || !d->msg_nr` for the editor
  decision and `if (d->msg_nr)` when copying the pre-existing message into the
  editor template;
- the now-unneeded note_data.given flag is deleted (struct field plus the
  `d.given = !!d.buf.len;` assignments);
- add() uses `d.msg_nr` in the existing-notes error branch, and append_edit()
  uses `d.msg_nr` to decide whether the deprecation warning applies.

Result: `git notes add -C <empty-blob> --allow-empty`, `-m "" --allow-empty`
and `-F /dev/null --allow-empty` store the empty note (visible in
`git notes list` as the empty blob object id) without ever launching the
editor, while a content-less `git notes add` still opens the editor as
intended.
EOF

if ! make -j1 > /tmp/oracle_build.log 2>&1; then
  echo "oracle: build failed:" >&2
  tail -20 /tmp/oracle_build.log >&2
  exit 1
fi
[ -x /app/src/git ] || { echo "oracle: no /app/src/git produced"; exit 1; }

# direct self-check of the fix
export GIT_EXEC_PATH=/app/src
R=/tmp/oracle-repro
rm -rf "$R" && mkdir -p "$R" && cd "$R" || exit 1
/app/src/git init -q .
/app/src/git config user.email oracle@localhost
/app/src/git config user.name oracle
echo content > file.txt
/app/src/git add file.txt
/app/src/git commit -qm init >/dev/null
empty=$(/app/src/git hash-object -w /dev/null)
if ! GIT_EDITOR=false /app/src/git notes add -C "$empty" --allow-empty > /tmp/oracle_repro.log 2>&1; then
  echo "oracle: repro still fails after fix:"; cat /tmp/oracle_repro.log
  exit 1
fi
listed=$(/app/src/git notes list HEAD)
[ "$listed" = "$empty" ] || { echo "oracle: notes list HEAD is '$listed', expected empty blob '$empty'"; exit 1; }
echo "oracle: fix applied, built, and repro passes (empty note stored, no editor launched, exit 0)"