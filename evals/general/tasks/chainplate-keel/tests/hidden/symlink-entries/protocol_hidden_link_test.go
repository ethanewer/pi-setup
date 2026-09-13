// chainplate-keel hidden case: symlink index entries for the consistency
// checker, with inputs the shipped regression test does not use.
//
// The shipped TestCheckConsistency drives symlinks named "foo" with target
// "bar" and sizes 0, SyntheticDirectorySize and 42. These cases use
// multi-component targets, a nested name, and sizes the shipped test does not
// try (1 byte, one below the synthetic size), exercising the same
// checkFileInfoConsistency path. Under the fixed semantics a symlink remains
// valid only at size zero: the synthetic-size exception applies to
// directories alone.
// FileInfo and the FileInfoType constants live in this package (bep_fileinfo.go),
// so no extra imports are needed beyond the testing harness.
package protocol

import (
	"testing"
)

func TestHiddenSymlinkZeroSizeDeep(t *testing.T) {
	// a symlink entry with a nested name and a multi-component target
	fi := FileInfo{
		Name:          "app/current",
		Type:          FileInfoTypeSymlink,
		SymlinkTarget: []byte("../../opt/release-2.0"),
	}
	err := checkFileInfoConsistency(fi)
	if err != nil {
		t.Errorf("zero-size symlink must be accepted, got %v", err)
	}
}

func TestHiddenSymlinkOneByte(t *testing.T) {
	// even a one-byte size on a symlink is a protocol error
	fi := FileInfo{
		Name:          "latest",
		Type:          FileInfoTypeSymlink,
		SymlinkTarget: []byte("target"),
		Size:          1,
	}
	err := checkFileInfoConsistency(fi)
	if err == nil {
		t.Error("symlink with size 1 must be rejected")
	}
}

func TestHiddenSymlinkJustBelowSynthetic(t *testing.T) {
	// a symlink must be exactly size zero; one below the synthetic size is
	// still rejected, even though that exact size is what directories are
	// permitted to carry
	fi := FileInfo{
		Name:          "link",
		Type:          FileInfoTypeSymlink,
		SymlinkTarget: []byte("somewhere"),
		Size:          SyntheticDirectorySize - 1,
	}
	err := checkFileInfoConsistency(fi)
	if err == nil {
		t.Error("symlink with size 127 must be rejected")
	}
}