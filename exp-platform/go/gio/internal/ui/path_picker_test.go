package ui

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPathPickerKindUsesExplicitMode(t *testing.T) {
	cases := []struct {
		name string
		spec pathPickerSpec
		want string
	}{
		{name: "path type directory", spec: pathPickerSpec{PathType: "directory"}, want: "directory"},
		{name: "path kind folder", spec: pathPickerSpec{PathKind: "folder"}, want: "directory"},
		{name: "path mode file", spec: pathPickerSpec{PathMode: "file", ID: "out_dir"}, want: "file"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := pathPickerKind(tc.spec); got != tc.want {
				t.Fatalf("pathPickerKind() = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestPathPickerKindInfersDirectories(t *testing.T) {
	cases := []pathPickerSpec{
		{ID: "ref_path"},
		{Key: "reference_library"},
		{ID: "out_dir"},
		{Label: "Output Directory"},
		{Tooltip: "Choose a cache folder"},
	}
	for _, spec := range cases {
		if got := pathPickerKind(spec); got != "directory" {
			t.Fatalf("pathPickerKind(%#v) = %q, want directory", spec, got)
		}
	}
}

func TestPathPickerKindDefaultsToFile(t *testing.T) {
	spec := pathPickerSpec{ID: "bam_path", Label: "Input BAM"}
	if got := pathPickerKind(spec); got != "file" {
		t.Fatalf("pathPickerKind() = %q, want file", got)
	}
}

func TestDefaultLocationForPathUsesCurrentPathOrExistingParent(t *testing.T) {
	root := t.TempDir()
	nested := filepath.Join(root, "nested")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	filePath := filepath.Join(nested, "sample.bam")
	if err := os.WriteFile(filePath, []byte("sample"), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}

	if got := defaultLocationForPath(nested, root); got != nested {
		t.Fatalf("directory default = %q, want %q", got, nested)
	}
	if got := defaultLocationForPath(filePath, root); got != nested {
		t.Fatalf("file default = %q, want parent %q", got, nested)
	}
	missingChild := filepath.Join(nested, "missing.fa")
	if got := defaultLocationForPath(missingChild, root); got != nested {
		t.Fatalf("missing child default = %q, want parent %q", got, nested)
	}
}
