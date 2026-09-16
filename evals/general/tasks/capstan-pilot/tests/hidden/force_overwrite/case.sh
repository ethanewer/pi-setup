#!/bin/bash
# Hidden case 2: force-overwrite an EXISTING non-empty note with
# `git notes add -f -F /dev/null --allow-empty`, with an editor that records
# invocation and fails. The upstream golden test never uses -f and never starts
# from a pre-existing note.
set -u
GITBIN=${GITBIN:-/app/src/git}
export GIT_EXEC_PATH=$(dirname "$GITBIN")
WORK=$(mktemp -d /tmp/hc-force.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

"$GITBIN" init -q .
"$GITBIN" config user.email hc@localhost
"$GITBIN" config user.name hc
printf 'data\n' > d.txt
"$GITBIN" add d.txt
"$GITBIN" commit -qm init

# a real, non-empty note first (this must succeed without the editor on any tree)
"$GITBIN" notes add -m "original contents" HEAD >/dev/null 2>&1 || { echo "FAIL hc2: could not store the initial note"; exit 1; }
[ "$("$GITBIN" notes show HEAD 2>/dev/null)" = "original contents" ] || { echo "FAIL hc2: initial note contents not as stored"; exit 1; }

empty=$("$GITBIN" hash-object -w /dev/null)
MARKER=$(mktemp /tmp/hc2-marker.XXXXXX); rm -f "$MARKER"
ED=$(mktemp /tmp/hc2-editor.XXXXXX)
printf '#!/bin/sh\necho "editor was invoked" >&2\ntouch %s\nexit 1\n' "$MARKER" > "$ED"
chmod +x "$ED"

out=$(GIT_EDITOR="$ED" "$GITBIN" notes add -f -F /dev/null --allow-empty HEAD 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL hc2: force-add exited $rc"; echo "$out" | sed 's/^/    /'; exit 1
fi
if [ -e "$MARKER" ]; then
  echo "FAIL hc2: the editor was invoked although -F supplied the contents"; exit 1
fi
if [ "$("$GITBIN" notes list HEAD 2>/dev/null)" != "$empty" ]; then
  echo "FAIL hc2: notes list HEAD is not the empty blob '$empty'"; exit 1
fi
# the overwrite must have REPLACED the old contents with the empty note
if "$GITBIN" notes show HEAD > show.out 2>/dev/null; then
  if [ -s show.out ]; then
    echo "FAIL hc2: note still has contents after overwrite with empty"; cat show.out; exit 1
  fi
else
  # older git may not distinguish empty note from missing; then list already proved storage
  :
fi
echo "PASS hc2"
exit 0