#!/bin/bash
# bollard-inlet reproduction: ignore rules must load when .stignore is a
# symlink to the real rules file.
#
# Usage: bash repro.sh [CHECKOUT]
#   CHECKOUT defaults to /app/src; any syncthing checkout works.
#
# Contract (see instruction.md):
#   - run against a BUGGY checkout: exits non-zero and prints the
#     "too many levels of symbolic links" diagnostic to stdout;
#   - run against a FIXED checkout: exits 0 and prints a passing test line
#     from the project's own runner.
set -u

CHECKOUT="${1:-/app/src}"
if [ ! -f "$CHECKOUT/go.mod" ]; then
    echo "not a syncthing checkout (no go.mod): $CHECKOUT" >&2
    exit 2
fi
cd "$CHECKOUT" || { echo "cannot cd into $CHECKOUT" >&2; exit 2; }

TEST_FILE=lib/ignore/bollard_repro_test.go
mkdir -p lib/ignore

# Self-contained regression-the-bug test: .stignore is a symlink to the real
# rules file stored under a different name in the same folder.
cat > "$TEST_FILE" <<'GOEOF'
//go:build !windows
package ignore

import (
	"testing"

	"github.com/syncthing/syncthing/lib/fs"
)

// Symlinked .stignore must load and apply its patterns.
func TestBollardReproSymlinkedStignore(t *testing.T) {
	testFS := fs.NewFilesystem(fs.FilesystemTypeBasic, t.TempDir())

	if err := fs.WriteFile(testFS, "real-rules.txt", []byte("repro-*.tmp\n"), 0o666); err != nil {
		t.Fatal(err)
	}
	if err := testFS.CreateSymlink("real-rules.txt", ".stignore"); err != nil {
		t.Fatal(err)
	}

	pats := New(testFS, WithCache(true))
	if err := pats.Load(".stignore"); err != nil {
		t.Fatal(err)
	}

	if !pats.Match("repro-a.tmp").IsIgnored() {
		t.Error("repro-*.tmp should be ignored via the symlinked .stignore")
	}
	if pats.Match("repro-a.txt").IsIgnored() {
		t.Error("repro-a.txt should not be ignored")
	}
}
GOEOF

go test ./lib/ignore/ -run "TestBollardReproSymlinkedStignore" -v
rc=$?
if [ $rc -ne 0 ]; then
    echo "* reproduced: symlinked .stignore rules NOT loaded (diagnostic above)" >&2
fi
exit $rc