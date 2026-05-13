package bundle

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadStringTablePreservesHashInsideQuotedValue(t *testing.T) {
	path := writeStringTable(t, `
"hash" = "value # inside" # outside
"plain" = "value" # outside
`)

	table, err := readStringTable(path)
	if err != nil {
		t.Fatal(err)
	}

	if table["hash"] != "value # inside" {
		t.Fatalf("hash = %q, want value # inside", table["hash"])
	}
	if table["plain"] != "value" {
		t.Fatalf("plain = %q, want value", table["plain"])
	}
}

func TestReadStringTableRejectsEmptyQuotedStringTokens(t *testing.T) {
	tests := map[string]string{
		"missing-key":   ` = "value"`,
		"missing-value": `"key" = `,
	}

	for name, content := range tests {
		t.Run(name, func(t *testing.T) {
			path := writeStringTable(t, content)
			if _, err := readStringTable(path); err == nil {
				t.Fatal("readStringTable() error = nil, want error")
			}
		})
	}
}

func writeStringTable(t *testing.T, content string) string {
	t.Helper()
	name := strings.NewReplacer("/", "_", " ", "_").Replace(t.Name())
	root := filepath.Join("testdata-out", name)
	if err := os.RemoveAll(root); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(root) })

	path := filepath.Join(root, "strings.toml")
	if err := os.WriteFile(path, []byte(strings.TrimSpace(content)+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}
