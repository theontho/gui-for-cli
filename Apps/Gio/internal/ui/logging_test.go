package ui

import (
	"testing"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

func TestStringLabelRendersMissingKey(t *testing.T) {
	app := &GioApp{bundle: &bundle.AppBundle{Strings: map[string]string{}}}

	if got := app.stringLabel("bundle.missing.title", "Fallback title"); got != "bundle.missing.title" {
		t.Fatalf("missing string = %q, want key", got)
	}
}

func TestStringFormatUsesLocalizedTemplate(t *testing.T) {
	app := &GioApp{bundle: &bundle.AppBundle{Strings: map[string]string{
		"app.test.format": "Hello %{name}",
	}}}

	if got := app.stringFormat("app.test.format", "Hi %{name}", map[string]string{"name": "Ada"}); got != "Hello Ada" {
		t.Fatalf("formatted string = %q, want localized template", got)
	}
}
