package bundle

import (
	"testing"
)

func TestLoadDecodesFullWGSExtractManifest(t *testing.T) {
	repoRoot := testRepoRoot(t)
	loaded, err := Load(LoadOptions{RepoRoot: repoRoot})
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if loaded.Manifest.DisplayName == "" || loaded.Manifest.DisplayName == "bundle.displayName" {
		t.Fatalf("display name was not localized: %q", loaded.Manifest.DisplayName)
	}
	library := findPage(loaded.Manifest.Pages, "library")
	if library == nil {
		t.Fatal("library page was not loaded")
	}
	section := findSection(library.Sections, "databases-tools")
	if section == nil || section.DataSource == nil {
		t.Fatal("section data source was not decoded")
	}
	control := findControl(library.Sections, "reference_genomes")
	if control == nil {
		t.Fatal("libraryList control was not decoded")
	}
	if control.Kind != "libraryList" || control.DataSource == nil || len(control.Columns) == 0 || len(control.RowActions) == 0 {
		t.Fatalf("libraryList missing rich fields: %#v", control)
	}
	if control.RowActions[0].IconOnly != true || len(control.RowActions[0].VisibleWhen) == 0 {
		t.Fatalf("row action missing icon/visibility metadata: %#v", control.RowActions[0])
	}
	settings := findControl(loaded.Manifest.Pages, "wgs_settings")
	if settings == nil || settings.ConfigFile == nil || settings.ConfigFile.Bootstrap == nil {
		t.Fatal("config editor metadata was not decoded")
	}
	if loaded.LocalizationCode == "" || len(loaded.LocalizationOptions) < 2 {
		t.Fatalf("localization metadata was not loaded: code=%q options=%d", loaded.LocalizationCode, len(loaded.LocalizationOptions))
	}
}

func TestLoadUsesRequestedLocalizationOverlay(t *testing.T) {
	repoRoot := testRepoRoot(t)
	loaded, err := Load(LoadOptions{RepoRoot: repoRoot, LocalizationCode: "ar"})
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if loaded.LocalizationCode != "ar" {
		t.Fatalf("LocalizationCode = %q, want ar", loaded.LocalizationCode)
	}
	if loaded.Strings["language.layoutDirection"] != "rtl" {
		t.Fatalf("language.layoutDirection = %q, want rtl", loaded.Strings["language.layoutDirection"])
	}
	foundArabic := false
	for _, option := range loaded.LocalizationOptions {
		if option.Code == "ar" && option.DisplayName != "" && option.DisplayName != "ar" {
			foundArabic = true
		}
	}
	if !foundArabic {
		t.Fatalf("Arabic option not discovered/localized: %#v", loaded.LocalizationOptions)
	}
}

func testRepoRoot(t *testing.T) string {
	t.Helper()
	repoRoot := findRepoRoot()
	if repoRoot == "" {
		t.Fatal("repository root was not found")
	}
	return repoRoot
}

func findPage(pages []Page, id string) *Page {
	for index := range pages {
		if pages[index].ID == id {
			return &pages[index]
		}
	}
	return nil
}

func findSection(sections []Section, id string) *Section {
	for index := range sections {
		if sections[index].ID == id {
			return &sections[index]
		}
	}
	return nil
}

func findControl(pagesOrSections any, id string) *Control {
	switch typed := pagesOrSections.(type) {
	case []Page:
		for _, page := range typed {
			if control := findControl(page.Sections, id); control != nil {
				return control
			}
		}
	case []Section:
		for sectionIndex := range typed {
			for controlIndex := range typed[sectionIndex].Controls {
				if typed[sectionIndex].Controls[controlIndex].ID == id {
					return &typed[sectionIndex].Controls[controlIndex]
				}
			}
		}
	}
	return nil
}
