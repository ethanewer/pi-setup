#!/bin/bash
# Hidden case 3: `git notes add -m "" --allow-empty` run FROM A SUBDIRECTORY of
# the repository (non-empty cwd prefix for object resolution), with an editor
# that records invocation and fails, followed by verification that the empty
# note was really stored. The upstream golden test always runs from the repo
# root and never verifies the stored object.
set -u
GITBIN=${GITBIN:-/app/src/git}
export GIT_EXEC_PATH=$(dirname "$GITBIN")
WORK=$(mktemp -d /tmp/hc-sub.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

"$GITBIN" init -q .
"$GITBIN" config user.email hc@localhost
"$GITBIN" config user.name hc
mkdir -p proj/src
printf 'int main(void){return 0;}\n' > proj/src/main.c
"$GITBIN" add proj/src/main.c
"$GITBIN" commit -qm init

empty=$("$GITBIN" hash-object -w /dev/null)
MARKER=$(mktemp /tmp/hc3-marker.XXXXXX); rm -f "$MARKER"
ED=$(mktemp /tmp/hc3-editor.XXXXXX)
printf '#!/bin/sh\necho "editor was invoked" >&2\ntouch %s\nexit 1\n' "$MARKER" > "$ED"
chmod +x "$ED"

out=$(cd proj/src && GIT_EDITOR="$ED" "$GITBIN" notes add -m "" --allow-empty HEAD 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL hc3: notes add from subdir exited $rc"; echo "$out" | sed 's/^/    /'; exit 1
fi
if [ -e "$MARKER" ]; then
  echo "FAIL hc3: the editor was invoked although -m supplied the contents"; exit 1
fi
if [ "$("$GITBIN" notes list HEAD 2>/dev/null)" != "$empty" ]; then
  echo "FAIL hc3: notes list HEAD is not the empty blob '$empty'"; exit 1
fi
if ! "$GITBIN" notes show HEAD > show.out 2>/dev/null; then
  echo "FAIL hc3: git notes show HEAD failed"; exit 1
fi
if [ -s show.out ]; then
  echo "FAIL hc3: git notes show HEAD printed contents of a supposedly empty note"; cat show.out; exit 1
fi
# also prove a second empty note can be appended onto the first without an editor
out2=$(cd proj/src && GIT_EDITOR="$ED" "$GITBIN" notes append -F /dev/null --allow-empty HEAD 2>&1); rc2=$?
if [ "$rc2" -ne 0 ]; then
  echo "FAIL hc3: notes append from subdir exited $rc2"; echo "$out2" | sed 's/^/    /'; exit 1
fi
if [ -e "$MARKER" ]; then
  echo "FAIL hc3: the editor was invoked during the append"; exit 1
fi
if [ "$("$GITBIN" notes list HEAD 2>/dev/null)" != "$empty" ]; then
  echo "FAIL hc3: after append, notes list HEAD is not the empty blob '$empty'"; exit 1
fi
echo "PASS hc3"
exit 0