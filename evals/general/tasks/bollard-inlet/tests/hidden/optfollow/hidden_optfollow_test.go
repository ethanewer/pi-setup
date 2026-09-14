//go:build !windows
package fs

import (
	"bytes"
	"testing"

	"github.com/syncthing/syncthing/lib/build"
)

// The filesystem layer itself must expose OptFollow: opening with it
// follows the final symlink component, opening without it keeps refusing
// it (O_NOFOLLOW). This exercises the flag in lib/fs directly, not through
// the ignore loader.
func TestHiddenOptFollowOpensSymlink(t *testing.T) {
	if build.IsWindows {
		t.Skip("symlinks not supported on Windows")
	}

	testFS := NewFilesystem(FilesystemTypeBasic, t.TempDir())

	if err := WriteFile(testFS, "payload.txt", []byte("hidden-fs-payload\n"), 0o666); err != nil {
		t.Fatal(err)
	}
	if err := testFS.CreateSymlink("payload.txt", "link.txt"); err != nil {
		t.Fatal(err)
	}

	// Without OptFollow the open must refuse the final symlink component.
	if _, err := testFS.Open("link.txt"); err == nil {
		t.Error("Open must not follow the final symlink component")
	}

	// With OptFollow the open must follow it and read the target content.
	fd, err := testFS.OpenFile("link.txt", OptReadOnly|OptFollow, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer fd.Close()

	buf := make([]byte, 64)
	n, err := fd.Read(buf)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(buf[:n], []byte("hidden-fs-payload\n")) {
		t.Error("OptFollow read the wrong content through the symlink")
	}
}