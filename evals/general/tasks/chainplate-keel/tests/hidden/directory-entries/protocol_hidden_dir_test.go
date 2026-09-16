// chainplate-keel hidden case: directory index entries for the consistency
// checker, with inputs the shipped regression test does not use.
//
// The shipped TestCheckConsistency drives directories named "foo" with sizes
// 0, SyntheticDirectorySize (128) and 42. These cases use nested names, extra
// metadata fields, a deleted directory and sizes adjacent to or far from the
// synthetic size, exercising the same checkFileInfoConsistency path with a
// different input set. Under the fixed semantics:
//   - a directory carrying exactly the synthetic directory size is accepted,
//     including with a nested name, mtime/permissions or the deleted bit;
//   - a directory with any other nonzero size is still a protocol error.
// FileInfo and the FileInfoType constants live in this package (bep_fileinfo.go),
// so no extra imports are needed beyond the testing harness.
package protocol

import (
	"testing"
)

func TestHiddenDirSyntheticSizeDeep(t *testing.T) {
	// a real directory entry as stamped by scanning: synthetic directory
	// size, nested name, mtime and permissions all set
	fi := FileInfo{
		Name:        "photos/2026/trip",
		Type:        FileInfoTypeDirectory,
		Size:        SyntheticDirectorySize,
		ModifiedS:   1700000000,
		ModifiedNs:  42,
		Permissions: 0o755,
	}
	err := checkFileInfoConsistency(fi)
	if err != nil {
		t.Errorf("directory with synthetic size must be accepted, got %v", err)
	}
}

func TestHiddenDirSyntheticDeleted(t *testing.T) {
	// a deleted directory entry that still carries the synthetic size
	fi := FileInfo{
		Name:    "oldstuff",
		Deleted: true,
		Type:    FileInfoTypeDirectory,
		Size:    SyntheticDirectorySize,
	}
	err := checkFileInfoConsistency(fi)
	if err != nil {
		t.Errorf("deleted directory with synthetic size must be accepted, got %v", err)
	}
}

func TestHiddenDirJustBelowSynthetic(t *testing.T) {
	// a directory claiming a size of synthetic-1 is still a protocol error
	fi := FileInfo{
		Name: "vacation",
		Type: FileInfoTypeDirectory,
		Size: SyntheticDirectorySize - 1,
	}
	err := checkFileInfoConsistency(fi)
	if err == nil {
		t.Error("directory with size 127 must be rejected")
	}
}

func TestHiddenDirLargeSize(t *testing.T) {
	// a directory whose size looks like a real data file size, far from the
	// synthetic size, must still be rejected
	fi := FileInfo{
		Name: "backup",
		Type: FileInfoTypeDirectory,
		Size: 1 << 20,
	}
	err := checkFileInfoConsistency(fi)
	if err == nil {
		t.Error("directory with size 1 MiB must be rejected")
	}
}