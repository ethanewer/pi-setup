#!/bin/bash
# Hidden case 1: `git notes add -C <empty-blob> --allow-empty` on a NON-HEAD
# annotated object (the first commit, reached via a tag), with an editor that
# records invocation and fails. The upstream golden test only annotates HEAD
# and never inspects the stored note.
set -u
GITBIN=${GITBIN:-/app/src/git}
export GIT_EXEC_PATH=$(dirname "$GITBIN")
WORK=$(mktemp -d /tmp/hc-tag.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

"$GITBIN" init -q .
"$GITBIN" config user.email hc@localhost
"$GITBIN" config user.name hc
printf 'first\n' > f.txt
"$GITBIN" add f.txt
"$GITBIN" commit -qm one
"$GITBIN" tag -m tagmsg v1
printf 'second\n' >> f.txt
"$GITBIN" add f.txt
"$GITBIN" commit -qm two   # HEAD is now a different commit than the target

empty=$("$GITBIN" hash-object -w /dev/null)
MARKER=$(mktemp /tmp/hc1-marker.XXXXXX); rm -f "$MARKER"
ED=$(mktemp /tmp/hc1-editor.XXXXXX)
printf '#!/bin/sh\necho "editor was invoked" >&2\ntouch %s\nexit 1\n' "$MARKER" > "$ED"
chmod +x "$ED"

out=$(GIT_EDITOR="$ED" "$GITBIN" notes add -C "$empty" --allow-empty v1 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL hc1: notes add exited $rc"; echo "$out" | sed 's/^/    /'; exit 1
fi
if [ -e "$MARKER" ]; then
  echo "FAIL hc1: the editor was invoked although -C supplied the contents"; exit 1
fi
listed=$("$GITBIN" notes list v1 2>/dev/null)
if [ "$listed" != "$empty" ]; then
  echo "FAIL hc1: notes list v1 is '$listed', expected the empty blob '$empty'"; exit 1
fi
# the note must be stored and empty: show exits 0 with no output
if ! "$GITBIN" notes show v1 > show.out 2>/dev/null; then
  echo "FAIL hc1: git notes show v1 failed"; exit 1
fi
if [ -s show.out ]; then
  echo "FAIL hc1: git notes show v1 printed contents of a supposedly empty note"; cat show.out; exit 1
fi
# the OTHER commit (HEAD) must NOT have picked up the note
if "$GITBIN" notes list HEAD >/dev/null 2>&1; then
  echo "FAIL hc1: HEAD wrongly has a note"; exit 1
fi
echo "PASS hc1"
exit 0