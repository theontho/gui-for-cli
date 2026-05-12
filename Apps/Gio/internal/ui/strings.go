package ui

import "runtime"

var cancelButtonTitleAliases = []string{
	"actions.library.genome-management.ref-delete.confirm.cancelButtonTitle",
	"actions.library.databases-tools.gene-map-delete.confirm.cancelButtonTitle",
	"actions.library.databases-tools.bootstrap-library.confirm.cancelButtonTitle",
}

func (g *GioApp) stringLabelReuse(primaryKey string, fallback string, alternateKeys ...string) string {
	if g != nil && g.bundle != nil {
		for _, key := range alternateKeys {
			if value := g.bundle.Strings[key]; value != "" {
				return value
			}
		}
		if value := g.bundle.Strings[primaryKey]; value != "" {
			return value
		}
	}
	if fallback != "" {
		return fallback
	}
	if primaryKey != "" {
		return primaryKey
	}
	return fallback
}

func (g *GioApp) settingsTitle() string {
	return g.stringLabelReuse("app.settings.title", "Settings", "pages.settings.title")
}

func (g *GioApp) cancelButtonTitle() string {
	return g.stringLabelReuse("app.confirmation.cancelButton.title", "Cancel", cancelButtonTitleAliases...)
}

func (g *GioApp) openWorkspaceButtonTitle() string {
	alternateKeys := []string{}
	if runtime.GOOS == "darwin" {
		alternateKeys = append(alternateKeys, "actions.settings.settings-paths.open-bundle-workspace.title")
	}
	return g.stringLabelReuse("app.setup.openWorkspaceButton.title", "Open Bundle Workspace", alternateKeys...)
}
