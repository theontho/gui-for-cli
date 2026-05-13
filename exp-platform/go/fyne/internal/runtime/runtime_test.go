package runtime

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/theontho/gui-for-cli/apps/fyne/internal/bundle"
)

func TestRenderCommandAndConditions(t *testing.T) {
	context := map[string]string{"input": "sample.bam", "status": "downloaded"}
	action := bundle.Action{
		Command:     bundle.Command{Executable: "wgsextract", Arguments: []string{"analyze", "{{input}}"}},
		VisibleWhen: []bundle.ActionCondition{{Placeholder: "status", Equals: "downloaded"}},
	}
	if !ActionVisible(action, context) {
		t.Fatal("expected action to be visible")
	}
	executable, args, missing := RenderCommand(action.Command, context)
	if len(missing) != 0 || executable != "wgsextract" || len(args) != 2 || args[1] != "sample.bam" {
		t.Fatalf("unexpected render: executable=%q args=%v missing=%v", executable, args, missing)
	}
}

func TestMissingPlaceholdersDisableAction(t *testing.T) {
	command := bundle.Command{Executable: "tool", Arguments: []string{"--input", "{{input}}"}}
	missing := MissingPlaceholders(command, map[string]string{})
	if len(missing) != 1 || missing[0] != "input" {
		t.Fatalf("missing placeholders = %v", missing)
	}
}

func TestHydrateRowsFromGenericItems(t *testing.T) {
	control := bundle.Control{
		Columns:     []bundle.ListColumn{{ID: "name", Title: "Name"}, {ID: "status", Title: "Status"}},
		Items:       []bundle.ListItem{{Values: map[string]string{"id": "hg38", "name": "Human GRCh38", "status": "downloaded"}}},
		RowTemplate: &bundle.ListRow{ID: "{{id}}", Title: "{{name}}", Status: "{{status}}", Values: map[string]string{"name": "{{name}}"}},
	}
	rows := HydrateRows(control)
	if len(rows) != 1 || rows[0].ID != "hg38" || rows[0].Values["name"] != "Human GRCh38" {
		t.Fatalf("unexpected rows: %#v", rows)
	}
}

func TestRunDataSourceAppliesPayload(t *testing.T) {
	root := localTempDir(t)
	script := filepath.Join(root, "source.sh")
	content := "#!/bin/sh\nprintf '%s\\n' '{\"options\":[{\"id\":\"one\",\"title\":\"One\"}]}'\n"
	if err := os.WriteFile(script, []byte(content), 0o755); err != nil {
		t.Fatal(err)
	}
	model := NewModel(&bundle.AppBundle{BundleRoot: root, BundleWorkspaceRoot: filepath.Join(root, "workspace")})
	payload, err := model.RunDataSource(bundle.ScriptDataSource{Path: script}, nil)
	if err != nil {
		t.Fatal(err)
	}
	control := bundle.Control{}
	ApplyPayloadToControl(&control, payload)
	if len(control.Options) != 1 || control.Options[0].ID != "one" {
		t.Fatalf("unexpected control options: %#v", control.Options)
	}
}

func localTempDir(t *testing.T) string {
	t.Helper()
	root := filepath.Join("testdata-out", t.Name())
	if err := os.RemoveAll(root); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(root) })
	abs, err := filepath.Abs(root)
	if err != nil {
		t.Fatal(err)
	}
	return abs
}
