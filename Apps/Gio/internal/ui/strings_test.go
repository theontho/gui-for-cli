package ui

import (
	"testing"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

func TestStringLabelReusePrefersAlternateKey(t *testing.T) {
	app := &GioApp{bundle: &bundle.AppBundle{Strings: map[string]string{
		"app.settings.title":   "Settings",
		"pages.settings.title": "Einstellungen",
	}}}

	if got := app.stringLabelReuse("app.settings.title", "Settings", "pages.settings.title"); got != "Einstellungen" {
		t.Fatalf("reused string = %q, want alternate localized value", got)
	}
}

func TestStringLabelReuseFallsBackToDefaultText(t *testing.T) {
	app := &GioApp{bundle: &bundle.AppBundle{Strings: map[string]string{}}}

	if got := app.stringLabelReuse("app.setup.openWorkspaceButton.title", "Open Bundle Workspace", "actions.settings.settings-paths.open-bundle-workspace.title"); got != "Open Bundle Workspace" {
		t.Fatalf("fallback string = %q, want default text", got)
	}
}
