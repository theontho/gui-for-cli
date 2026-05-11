package ui

import "testing"

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
