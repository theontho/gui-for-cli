package bundle

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

type LoadOptions struct {
	BundleRoot         string
	BuiltinStringsRoot string
	RepoRoot           string
	LocalizationCode   string
}

var pageFileNamePattern = regexp.MustCompile(`^[A-Za-z0-9._-]+\.json$`)
var stringTableNamePattern = regexp.MustCompile(`^strings\.([A-Za-z0-9_-]+)\.toml$`)

func Load(options LoadOptions) (*AppBundle, error) {
	paths, err := resolvePaths(options)
	if err != nil {
		return nil, err
	}

	manifest, err := loadManifest(paths.bundleRoot)
	if err != nil {
		return nil, err
	}

	localizationOptions, err := loadLocalizationOptions(paths, manifest)
	if err != nil {
		return nil, fmt.Errorf("load localization options: %w", err)
	}
	localeCode := resolvedLocalizationCode(options.LocalizationCode, manifest.DefaultLocalizationCode, localizationOptions)

	stringTable, err := loadStringTable(paths, manifest, localeCode)
	if err != nil {
		return nil, fmt.Errorf("load strings: %w", err)
	}

	localizeManifest(&manifest, stringTable)

	return &AppBundle{
		Manifest:            manifest,
		BundleRoot:          paths.bundleRoot,
		BundleWorkspaceRoot: paths.bundleWorkspaceRoot,
		BuiltinStringsRoot:  paths.builtinStringsRoot,
		Strings:             stringTable,
		LocalizationCode:    localeCode,
		LocalizationOptions: localizationOptions,
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

func loadStringTable(paths *resolvedPaths, manifest Manifest, localeCode string) (map[string]string, error) {
	defaultCode := manifest.DefaultLocalizationCode
	if strings.TrimSpace(defaultCode) == "" {
		defaultCode = "en"
	}
	builtinBase, err := readStringTable(filepath.Join(paths.builtinStringsRoot, "strings.en.toml"))
	if err != nil {
		return nil, fmt.Errorf("load built-in English strings: %w", err)
	}
	builtinOverlay := map[string]string{}
	if localeCode != "en" {
		builtinOverlay, err = readOptionalStringTable(filepath.Join(paths.builtinStringsRoot, fmt.Sprintf("strings.%s.toml", localeCode)))
		if err != nil {
			return nil, fmt.Errorf("load built-in %s strings: %w", localeCode, err)
		}
	}
	bundleBase, err := readOptionalStringTable(filepath.Join(paths.bundleRoot, "strings", fmt.Sprintf("strings.%s.toml", defaultCode)))
	if err != nil {
		return nil, fmt.Errorf("load bundle %s strings: %w", defaultCode, err)
	}
	bundleOverlay := map[string]string{}
	if localeCode != defaultCode {
		bundleOverlay, err = readOptionalStringTable(filepath.Join(paths.bundleRoot, "strings", fmt.Sprintf("strings.%s.toml", localeCode)))
		if err != nil {
			return nil, fmt.Errorf("load bundle %s strings: %w", localeCode, err)
		}
	}
	return mergeTables(builtinBase, builtinOverlay, bundleBase, bundleOverlay), nil
}

func loadLocalizationOptions(paths *resolvedPaths, manifest Manifest) ([]LocalizationOption, error) {
	defaultCode := manifest.DefaultLocalizationCode
	if strings.TrimSpace(defaultCode) == "" {
		defaultCode = "en"
	}
	codes := map[string]struct{}{}
	for _, code := range availableLocaleCodes(paths.builtinStringsRoot) {
		codes[code] = struct{}{}
	}
	for _, code := range availableLocaleCodes(filepath.Join(paths.bundleRoot, "strings")) {
		codes[code] = struct{}{}
	}
	codes[defaultCode] = struct{}{}

	options := make([]LocalizationOption, 0, len(codes))
	for code := range codes {
		displayName := code
		if table, err := readOptionalStringTable(filepath.Join(paths.builtinStringsRoot, fmt.Sprintf("strings.%s.toml", code))); err != nil {
			return nil, err
		} else if table["language.name"] != "" {
			displayName = table["language.name"]
		}
		if table, err := readOptionalStringTable(filepath.Join(paths.bundleRoot, "strings", fmt.Sprintf("strings.%s.toml", code))); err != nil {
			return nil, err
		} else if table["language.name"] != "" {
			displayName = table["language.name"]
		}
		options = append(options, LocalizationOption{Code: code, DisplayName: displayName})
	}
	sort.Slice(options, func(i, j int) bool {
		if options[i].Code == defaultCode {
			return true
		}
		if options[j].Code == defaultCode {
			return false
		}
		return strings.ToLower(options[i].DisplayName) < strings.ToLower(options[j].DisplayName)
	})
	return options, nil
}

func availableLocaleCodes(directory string) []string {
	entries, err := os.ReadDir(directory)
	if err != nil {
		return nil
	}
	codes := []string{}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		matches := stringTableNamePattern.FindStringSubmatch(entry.Name())
		if len(matches) == 2 {
			codes = append(codes, matches[1])
		}
	}
	return codes
}

func resolvedLocalizationCode(requested string, defaultCode string, options []LocalizationOption) string {
	if strings.TrimSpace(defaultCode) == "" {
		defaultCode = "en"
	}
	requested = strings.TrimSpace(requested)
	if requested != "" && localeAvailable(requested, options) {
		return requested
	}
	if localeAvailable(defaultCode, options) {
		return defaultCode
	}
	if len(options) > 0 {
		return options[0].Code
	}
	return defaultCode
}

func localeAvailable(code string, options []LocalizationOption) bool {
	for _, option := range options {
		if option.Code == code {
			return true
		}
	}
	return false
}

func localizeManifest(manifest *Manifest, table map[string]string) {
	manifest.DisplayName = localizeText(manifest.DisplayName, table)
	manifest.Summary = localizeText(manifest.Summary, table)
	for referenceIndex := range manifest.ExitCodeReference {
		manifest.ExitCodeReference[referenceIndex].Title = localizeText(manifest.ExitCodeReference[referenceIndex].Title, table)
		manifest.ExitCodeReference[referenceIndex].Summary = localizeText(manifest.ExitCodeReference[referenceIndex].Summary, table)
	}
	for pageIndex := range manifest.Pages {
		page := &manifest.Pages[pageIndex]
		page.Title = localizeText(page.Title, table)
		page.Summary = localizeText(page.Summary, table)
		page.SidebarGroup = localizeText(page.SidebarGroup, table)

		for sectionIndex := range page.Sections {
			section := &page.Sections[sectionIndex]
			section.Title = localizeText(section.Title, table)
			section.Subtitle = localizeText(section.Subtitle, table)
			localizeActions(section.Actions, table)

			for controlIndex := range section.Controls {
				control := &section.Controls[controlIndex]
				control.Label = localizeText(control.Label, table)
				control.Placeholder = localizeText(control.Placeholder, table)
				control.Tooltip = localizeText(control.Tooltip, table)
				for columnIndex := range control.Columns {
					control.Columns[columnIndex].Title = localizeText(control.Columns[columnIndex].Title, table)
				}
				localizeRows(control.Rows, table)
				if control.RowTemplate != nil {
					localizeRow(control.RowTemplate, table)
				}
				localizeActions(control.RowActions, table)
				for optionIndex := range control.Options {
					localizeOption(&control.Options[optionIndex], table)
				}
				for settingIndex := range control.Settings {
					setting := &control.Settings[settingIndex]
					setting.Label = localizeText(setting.Label, table)
					setting.Placeholder = localizeText(setting.Placeholder, table)
					setting.Tooltip = localizeText(setting.Tooltip, table)
					for optionIndex := range setting.Options {
						localizeOption(&setting.Options[optionIndex], table)
					}
				}
			}
		}
	}
}

func localizeRows(rows []ListRow, table map[string]string) {
	for rowIndex := range rows {
		localizeRow(&rows[rowIndex], table)
	}
}

func localizeRow(row *ListRow, table map[string]string) {
	row.Title = localizeText(row.Title, table)
	row.Status = localizeText(row.Status, table)
	row.Tooltip = localizeText(row.Tooltip, table)
	for key, value := range row.Values {
		row.Values[key] = localizeText(value, table)
	}
	for tagIndex := range row.Tags {
		row.Tags[tagIndex].Title = localizeText(row.Tags[tagIndex].Title, table)
	}
}

func localizeOption(option *Option, table map[string]string) {
	option.Title = localizeText(option.Title, table)
	option.Status = localizeText(option.Status, table)
	option.Group = localizeText(option.Group, table)
}

func localizeActions(actions []Action, table map[string]string) {
	for actionIndex := range actions {
		action := &actions[actionIndex]
		action.Title = localizeText(action.Title, table)
		action.Tooltip = localizeText(action.Tooltip, table)
		action.DisabledTooltip = localizeText(action.DisabledTooltip, table)
		if action.Precheck != nil {
			action.Precheck.WarningMessage = localizeText(action.Precheck.WarningMessage, table)
		}
		if action.Confirm != nil {
			action.Confirm.Title = localizeText(action.Confirm.Title, table)
			action.Confirm.Message = localizeText(action.Confirm.Message, table)
			action.Confirm.ConfirmButtonTitle = localizeText(action.Confirm.ConfirmButtonTitle, table)
			action.Confirm.CancelButtonTitle = localizeText(action.Confirm.CancelButtonTitle, table)
			action.Confirm.RequiredText = localizeText(action.Confirm.RequiredText, table)
			action.Confirm.Prompt = localizeText(action.Confirm.Prompt, table)
		}
	}
}

func localizeText(value string, table map[string]string) string {
	if localized, ok := table[value]; ok {
		return localized
	}
	return value
}
