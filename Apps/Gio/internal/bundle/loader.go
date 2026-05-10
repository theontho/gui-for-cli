package bundle

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type LoadOptions struct {
	BundleRoot         string
	BuiltinStringsRoot string
	RepoRoot           string
}

var pageFileNamePattern = regexp.MustCompile(`^[A-Za-z0-9._-]+\.json$`)

func Load(options LoadOptions) (*AppBundle, error) {
	paths, err := resolvePaths(options)
	if err != nil {
		return nil, err
	}

	manifest, err := loadManifest(paths.bundleRoot)
	if err != nil {
		return nil, err
	}

	localeCode := manifest.DefaultLocalizationCode
	if strings.TrimSpace(localeCode) == "" {
		localeCode = "en"
	}

	builtinTable, err := readStringTable(filepath.Join(paths.builtinStringsRoot, "strings.en.toml"))
	if err != nil {
		return nil, fmt.Errorf("load built-in strings: %w", err)
	}
	bundleTable, err := readOptionalStringTable(filepath.Join(paths.bundleRoot, "strings", fmt.Sprintf("strings.%s.toml", localeCode)))
	if err != nil {
		return nil, fmt.Errorf("load bundle strings: %w", err)
	}

	localizeManifest(&manifest, mergeTables(builtinTable, bundleTable))

	return &AppBundle{
		Manifest:            manifest,
		BundleRoot:          paths.bundleRoot,
		BundleWorkspaceRoot: paths.bundleWorkspaceRoot,
		BuiltinStringsRoot:  paths.builtinStringsRoot,
	}, nil
}

type resolvedPaths struct {
	bundleRoot          string
	bundleWorkspaceRoot string
	builtinStringsRoot  string
}

func resolvePaths(options LoadOptions) (*resolvedPaths, error) {
	repoRoot := strings.TrimSpace(options.RepoRoot)
	if repoRoot == "" {
		repoRoot = findRepoRoot()
	}

	bundleRoot := strings.TrimSpace(options.BundleRoot)
	if bundleRoot == "" {
		if repoRoot == "" {
			exe, err := os.Executable()
			if err != nil {
				return nil, err
			}
			bundleRoot = filepath.Join(filepath.Dir(exe), "Examples", "WGSExtract")
		} else {
			bundleRoot = filepath.Join(repoRoot, "Examples", "WGSExtract")
		}
	}
	bundleRoot = filepath.Clean(bundleRoot)
	if _, err := os.Stat(filepath.Join(bundleRoot, "manifest.json")); err != nil {
		return nil, fmt.Errorf("bundle manifest not found at %s: %w", bundleRoot, err)
	}

	builtinStringsRoot := strings.TrimSpace(options.BuiltinStringsRoot)
	if builtinStringsRoot == "" {
		if repoRoot != "" {
			builtinStringsRoot = filepath.Join(repoRoot, "Sources", "GUIForCLICore", "Resources", "BuiltinStrings")
		} else {
			exe, err := os.Executable()
			if err != nil {
				return nil, err
			}
			builtinStringsRoot = filepath.Join(filepath.Dir(exe), "Resources", "BuiltinStrings")
		}
	}
	builtinStringsRoot = filepath.Clean(builtinStringsRoot)
	if _, err := os.Stat(filepath.Join(builtinStringsRoot, "strings.en.toml")); err != nil {
		return nil, fmt.Errorf("built-in strings not found at %s: %w", builtinStringsRoot, err)
	}

	workspaceRoot, err := os.UserConfigDir()
	if err != nil {
		return nil, fmt.Errorf("resolve config directory: %w", err)
	}
	workspaceRoot = filepath.Join(workspaceRoot, "gui-for-cli", "gio-workspace", filepath.Base(bundleRoot))

	return &resolvedPaths{
		bundleRoot:          bundleRoot,
		bundleWorkspaceRoot: workspaceRoot,
		builtinStringsRoot:  builtinStringsRoot,
	}, nil
}

func findRepoRoot() string {
	candidates := make([]string, 0, 4)
	if wd, err := os.Getwd(); err == nil {
		candidates = append(candidates, wd)
	}
	if exe, err := os.Executable(); err == nil {
		candidates = append(candidates, filepath.Dir(exe))
	}

	for _, candidate := range candidates {
		current := candidate
		for {
			if hasRepoMarkers(current) {
				return current
			}
			parent := filepath.Dir(current)
			if parent == current {
				break
			}
			current = parent
		}
	}
	return ""
}

func hasRepoMarkers(path string) bool {
	if path == "" {
		return false
	}
	markers := []string{
		filepath.Join(path, "Examples", "WGSExtract", "manifest.json"),
		filepath.Join(path, "Sources", "GUIForCLICore", "Resources", "BuiltinStrings", "strings.en.toml"),
	}
	for _, marker := range markers {
		if _, err := os.Stat(marker); err != nil {
			return false
		}
	}
	return true
}

func loadManifest(bundleRoot string) (Manifest, error) {
	manifestPath := filepath.Join(bundleRoot, "manifest.json")
	manifestBytes, err := os.ReadFile(manifestPath)
	if err != nil {
		return Manifest{}, err
	}

	var manifest map[string]any
	if err := json.Unmarshal(manifestBytes, &manifest); err != nil {
		return Manifest{}, err
	}

	rawPages, ok := manifest["pages"].([]any)
	if !ok {
		return Manifest{}, errors.New("manifest pages must be a string array")
	}

	pageFiles := make([]string, 0, len(rawPages))
	loadedPages := make([]json.RawMessage, 0, len(rawPages))
	for _, rawPage := range rawPages {
		fileName, ok := rawPage.(string)
		if !ok || !pageFileNamePattern.MatchString(fileName) || strings.Contains(fileName, "/") || strings.Contains(fileName, `\`) {
			return Manifest{}, fmt.Errorf("invalid page file name: %v", rawPage)
		}

		pagePath := filepath.Join(bundleRoot, "pages", fileName)
		pageBytes, err := os.ReadFile(pagePath)
		if err != nil {
			return Manifest{}, fmt.Errorf("read page %s: %w", fileName, err)
		}
		pageFiles = append(pageFiles, fileName)
		loadedPages = append(loadedPages, json.RawMessage(pageBytes))
	}
	manifest["pages"] = loadedPages

	rebuiltBytes, err := json.Marshal(manifest)
	if err != nil {
		return Manifest{}, err
	}

	var result Manifest
	if err := json.Unmarshal(rebuiltBytes, &result); err != nil {
		return Manifest{}, err
	}
	result.PageFiles = pageFiles
	return result, nil
}

func mergeTables(tables ...map[string]string) map[string]string {
	merged := map[string]string{}
	for _, table := range tables {
		for key, value := range table {
			merged[key] = value
		}
	}
	return merged
}

func localizeManifest(manifest *Manifest, table map[string]string) {
	manifest.DisplayName = localizeText(manifest.DisplayName, table)
	manifest.Summary = localizeText(manifest.Summary, table)
	for pageIndex := range manifest.Pages {
		page := &manifest.Pages[pageIndex]
		page.Title = localizeText(page.Title, table)
		page.Summary = localizeText(page.Summary, table)
		page.SidebarGroup = localizeText(page.SidebarGroup, table)

		for sectionIndex := range page.Sections {
			section := &page.Sections[sectionIndex]
			section.Title = localizeText(section.Title, table)
			section.Subtitle = localizeText(section.Subtitle, table)

			for controlIndex := range section.Controls {
				control := &section.Controls[controlIndex]
				control.Label = localizeText(control.Label, table)
				control.Placeholder = localizeText(control.Placeholder, table)
				control.Tooltip = localizeText(control.Tooltip, table)
				for optionIndex := range control.Options {
					control.Options[optionIndex].Title = localizeText(control.Options[optionIndex].Title, table)
				}
				for settingIndex := range control.Settings {
					setting := &control.Settings[settingIndex]
					setting.Label = localizeText(setting.Label, table)
					setting.Placeholder = localizeText(setting.Placeholder, table)
					setting.Tooltip = localizeText(setting.Tooltip, table)
					for optionIndex := range setting.Options {
						setting.Options[optionIndex].Title = localizeText(setting.Options[optionIndex].Title, table)
					}
				}
			}

			for actionIndex := range section.Actions {
				action := &section.Actions[actionIndex]
				action.Title = localizeText(action.Title, table)
				action.Tooltip = localizeText(action.Tooltip, table)
				action.DisabledTooltip = localizeText(action.DisabledTooltip, table)
			}
		}
	}
}

func localizeText(value string, table map[string]string) string {
	if localized, ok := table[value]; ok {
		return localized
	}
	return value
}
