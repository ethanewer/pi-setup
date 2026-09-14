//go:build !windows
package ignore

import (
	"path/filepath"
	"testing"

	"github.com/syncthing/syncthing/lib/build"
	"github.com/syncthing/syncthing/lib/fs"
)

// The .stignore of a folder may be a symlink whose TARGET lives in a
// nested subdirectory of the folder (not next to the symlink as in the
// upstream regression test). The rules must still be loaded and applied.
func TestHiddenStignoreSymlinkTargetInSubdir(t *testing.T) {
	if build.IsWindows {
		t.Skip("symlinks not supported on Windows")
	}

	testFS := fs.NewFilesystem(fs.FilesystemTypeBasic, t.TempDir())

	if err := testFS.Mkdir("rules", 0o777); err != nil {
		t.Fatal(err)
	}
	// Rules live in rules/ignores.txt; .stignore is a relative symlink to it.
	if err := fs.WriteFile(testFS, "rules/ignores.txt", []byte("hidden-sub-*.log\n"), 0o666); err != nil {
		t.Fatal(err)
	}
	if err := testFS.CreateSymlink("rules/ignores.txt", ".stignore"); err != nil {
		t.Fatal(err)
	}

	pats := New(testFS, WithCache(true))
	if err := pats.Load(".stignore"); err != nil {
		t.Fatal(err)
	}

	if !pats.Match("hidden-sub-alpha.log").IsIgnored() {
		t.Error("hidden-sub-*.log should be ignored through the symlinked .stignore")
	}
	if pats.Match("visible.txt").IsIgnored() {
		t.Error("visible.txt should not be ignored")
	}
	if pats.Match(filepath.Join("rules", "ignores.txt")).IsIgnored() {
		t.Error("the rules file itself should not be ignored")
	}
}