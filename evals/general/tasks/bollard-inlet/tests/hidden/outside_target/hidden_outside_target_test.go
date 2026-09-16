//go:build !windows
package ignore

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/syncthing/syncthing/lib/build"
	"github.com/syncthing/syncthing/lib/fs"
)

// The .stignore of a folder may be a symlink pointing RELATIVE OUTSIDE of
// the folder itself (a shared rules file kept next to the folder). The
// rules must still be loaded and applied.
func TestHiddenStignoreSymlinkTargetOutsideFolder(t *testing.T) {
	if build.IsWindows {
		t.Skip("symlinks not supported on Windows")
	}

	// Two distinct temp dirs under a common parent: `outside` holds the
	// real rules file, `folder` is the folder root. The symlink target
	// string walks ".." out of the folder.
	outside := t.TempDir()
	folder := t.TempDir()

	if err := os.WriteFile(filepath.Join(outside, "shared-ignores"), []byte("hidden-out-*.tmp\n"), 0o666); err != nil {
		t.Fatal(err)
	}

	testFS := fs.NewFilesystem(fs.FilesystemTypeBasic, folder)

	rel := filepath.Join("..", filepath.Base(outside), "shared-ignores")
	if err := testFS.CreateSymlink(rel, ".stignore"); err != nil {
		t.Fatal(err)
	}

	pats := New(testFS, WithCache(true))
	if err := pats.Load(".stignore"); err != nil {
		t.Fatal(err)
	}

	if !pats.Match("hidden-out-a.tmp").IsIgnored() {
		t.Error("hidden-out-*.tmp should be ignored through the symlinked .stignore")
	}
	if pats.Match("hidden-out-a.txt").IsIgnored() {
		t.Error("hidden-out-a.txt should not be ignored")
	}
}