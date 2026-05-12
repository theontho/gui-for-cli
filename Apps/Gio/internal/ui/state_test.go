package ui

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"gioui.org/widget"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

func TestAutoSaveConfigWritesSettingChanges(t *testing.T) {
	workspace := t.TempDir()
	configPath := filepath.Join(workspace, "settings.toml")
	control := bundle.Control{
		ID:   "settings",
		Kind: "configEditor",
		ConfigFile: &bundle.ConfigFile{
			Path: configPath,
		},
		Settings: []bundle.ConfigSetting{
			{ID: "threads", Key: "threads", Value: "4"},
		},
	}
	app := &GioApp{
		bundle: &bundle.AppBundle{
			BundleRoot:          workspace,
			BundleWorkspaceRoot: workspace,
			Manifest: bundle.Manifest{
				Pages: []bundle.Page{{
					Sections: []bundle.Section{{
						Controls: []bundle.Control{control},
					}},
				}},
			},
		},
		textFields:       map[string]*widget.Editor{},
		configPathFields: map[string]*widget.Editor{},
		toggles:          map[string]*widget.Bool{},
		dropdowns:        map[string]*dropdownState{},
		configPaths:      map[string]string{"settings": configPath},
		configValues:     map[string]string{},
		state: bundleState{
			ConfigFilePaths: map[string]string{},
			FieldValues:     map[string]string{},
			CheckedOptions:  map[string][]string{},
		},
	}
	app.configPathEditorFor(control)
	app.editorFor("threads", "8")

	app.autoSaveConfig(control)

	bytes, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if !strings.Contains(string(bytes), `threads = "8"`) {
		t.Fatalf("config = %q, want updated threads value", string(bytes))
	}
	if len(app.terminalEntries) != 0 {
		t.Fatalf("autosave should not append success logs, got %#v", app.terminalEntries)
	}
}
