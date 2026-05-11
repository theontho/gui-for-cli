package ui

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

type bundleState struct {
	LocalizationCode *string             `json:"localizationCode"`
	ConfigFilePaths  map[string]string   `json:"configFilePaths"`
	FieldValues      map[string]string   `json:"fieldValues"`
	CheckedOptions   map[string][]string `json:"checkedOptions"`
	SelectedPageID   string              `json:"selectedPageID"`
	SetupRun         *setupRunState      `json:"setupRun"`
	IconSet          string              `json:"iconSet"`
	ColorTheme       string              `json:"colorTheme"`
	WebUIFont        string              `json:"webUIFont"`
	SidebarVisible   *bool               `json:"gioSidebarVisible,omitempty"`
	TerminalVisible  *bool               `json:"gioTerminalVisible,omitempty"`
}

type configBinding struct {
	control bundle.Control
	setting bundle.ConfigSetting
}

func (g *GioApp) bootstrapState() error {
	if err := os.MkdirAll(g.bundle.BundleWorkspaceRoot, 0o755); err != nil {
		return err
	}
	state, err := loadBundleState(g.statePath())
	if err != nil {
		return err
	}
	g.state = state
	if g.state.ConfigFilePaths == nil {
		g.state.ConfigFilePaths = map[string]string{}
	}
	if g.state.FieldValues == nil {
		g.state.FieldValues = map[string]string{}
	}
	if g.state.CheckedOptions == nil {
		g.state.CheckedOptions = map[string][]string{}
	}
	g.normalizePreferences()
	g.setupRun = g.state.SetupRun
	g.initConfigPaths()
	return g.loadInitialConfigs()
}

func loadBundleState(path string) (bundleState, error) {
	bytes, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return bundleState{}, nil
		}
		return bundleState{}, fmt.Errorf("load state: %w", err)
	}
	var state bundleState
	if err := json.Unmarshal(bytes, &state); err != nil {
		return bundleState{}, fmt.Errorf("decode state: %w", err)
	}
	return state, nil
}

func (g *GioApp) saveState() {
	g.state.SetupRun = g.setupRun
	if err := os.MkdirAll(g.bundle.BundleWorkspaceRoot, 0o755); err != nil {
		g.appendLog(fmt.Sprintf("Could not create workspace: %v", err))
		return
	}
	bytes, err := json.MarshalIndent(g.state, "", "  ")
	if err != nil {
		g.appendLog(fmt.Sprintf("Could not encode state: %v", err))
		return
	}
	if err := os.WriteFile(g.statePath(), append(bytes, '\n'), 0o644); err != nil {
		g.appendLog(fmt.Sprintf("Could not save state: %v", err))
	}
}

func (g *GioApp) statePath() string {
	return filepath.Join(g.bundle.BundleWorkspaceRoot, "state.json")
}

func (g *GioApp) initConfigPaths() {
	for _, control := range g.configEditorControls() {
		if control.ConfigFile == nil {
			continue
		}
		path := control.ConfigFile.Path
		if persisted := g.state.ConfigFilePaths[control.ID]; strings.TrimSpace(persisted) != "" {
			path = persisted
		}
		g.configPaths[control.ID] = g.resolvePathTokens(path, "")
	}
}

func (g *GioApp) loadInitialConfigs() error {
	var firstErr error
	for _, control := range g.configEditorControls() {
		if control.ConfigFile == nil {
			continue
		}
		if err := g.bootstrapConfigIfNeeded(control); err != nil && firstErr == nil {
			firstErr = err
		}
		if err := g.loadConfig(control); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

func (g *GioApp) bootstrapConfigIfNeeded(control bundle.Control) error {
	if control.ConfigFile == nil || control.ConfigFile.Bootstrap == nil || control.ConfigFile.Bootstrap.Script == nil {
		return nil
	}
	path := g.configPaths[control.ID]
	if _, err := os.Stat(path); err == nil {
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if control.ConfigFile.Bootstrap.Mode != "" && control.ConfigFile.Bootstrap.Mode != "createIfMissing" {
		return nil
	}
	script := control.ConfigFile.Bootstrap.Script
	executable, err := g.resolveBundlePath(script.Path)
	if err != nil {
		return err
	}
	ctx := g.contextValues(map[string]string{"configPath": path, "configDir": filepath.Dir(path)})
	args := interpolateAll(script.Args, ctx)
	command, err := shellCommand(executable, args)
	if err != nil {
		return err
	}
	command.Dir = g.bundle.BundleRoot
	if script.WorkingDirectory != "" {
		command.Dir, err = g.resolveBundlePath(script.WorkingDirectory)
		if err != nil {
			return err
		}
	}
	command.Env = append(os.Environ(), g.environment(ctx, script.Env)...)
	output, err := command.CombinedOutput()
	if err != nil {
		return fmt.Errorf("bootstrap config %s: %w: %s", control.ID, err, strings.TrimSpace(string(output)))
	}
	g.appendLog(fmt.Sprintf("Bootstrapped settings file %s", path))
	return nil
}

func (g *GioApp) loadConfig(control bundle.Control) error {
	if control.ConfigFile == nil {
		return nil
	}
	editor := g.configPathEditorFor(control)
	path := g.resolvePathTokens(editor.Text(), "")
	if strings.TrimSpace(path) == "" {
		return fmt.Errorf("choose a settings file path before loading %s", control.Label)
	}
	g.configPaths[control.ID] = path
	g.state.ConfigFilePaths[control.ID] = path
	values, err := parseFlatTomlFile(path)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return err
		}
		values = map[string]string{}
	}
	for _, setting := range control.Settings {
		value := values[setting.Key]
		if value == "" {
			value = setting.Value
		}
		key := configValueKey(control, setting)
		g.configValues[key] = value
		if field := g.editorFor(setting.ID, value); field.Text() != value {
			field.SetText(value)
		}
		if toggle := g.toggles[setting.ID]; toggle != nil {
			toggle.Value = value == "true"
		}
		if dropdown := g.dropdowns[setting.ID]; dropdown != nil {
			dropdown.index = selectedOptionIndex(dropdown.options, value)
		}
	}
	g.syncSharedFieldsFromConfig(control)
	g.saveState()
	g.appendLog(fmt.Sprintf("Loaded settings from %s", path))
	return nil
}

func (g *GioApp) saveConfig(control bundle.Control) error {
	return g.writeConfig(control, true)
}

func (g *GioApp) autoSaveConfig(control bundle.Control) {
	if err := g.writeConfig(control, false); err != nil {
		g.appendLog(fmt.Sprintf("Save settings failed: %v", err))
	}
}

func (g *GioApp) writeConfig(control bundle.Control, logSuccess bool) error {
	if control.ConfigFile == nil {
		return nil
	}
	g.syncConfigFromWidgets()
	editor := g.configPathEditorFor(control)
	path := g.resolvePathTokens(editor.Text(), "")
	if strings.TrimSpace(path) == "" {
		return fmt.Errorf("choose a settings file path before saving %s", control.Label)
	}
	values := map[string]string{}
	for _, setting := range control.Settings {
		values[setting.Key] = g.configValue(control, setting)
	}
	if err := writeFlatTomlFile(path, values); err != nil {
		return err
	}
	g.configPaths[control.ID] = path
	g.state.ConfigFilePaths[control.ID] = path
	g.saveState()
	if logSuccess {
		g.appendLog(fmt.Sprintf("Saved %d settings to %s", len(values), path))
	}
	return nil
}

func (g *GioApp) persistFormState() {
	g.syncConfigFromWidgets()
	g.state.FieldValues = map[string]string{}
	for id, editor := range g.textFields {
		if len(g.configSettingBindings(id)) == 0 && !strings.HasPrefix(id, "preference:") {
			g.state.FieldValues[id] = editor.Text()
		}
	}
	for id, dropdown := range g.dropdowns {
		if len(dropdown.options) == 0 || len(g.configSettingBindings(id)) != 0 || strings.HasPrefix(id, "preference:") {
			continue
		}
		g.state.FieldValues[id] = dropdown.options[dropdown.index].ID
	}
	for id, toggle := range g.toggles {
		if len(g.configSettingBindings(id)) == 0 && !strings.HasPrefix(id, "preference:") {
			g.state.FieldValues[id] = strconv.FormatBool(toggle.Value)
		}
	}
	g.state.CheckedOptions = map[string][]string{}
	for id, group := range g.checkboxGroups {
		g.state.CheckedOptions[id] = sortedSelectedIDs(group)
	}
	g.saveState()
}

func (g *GioApp) controlValue(control bundle.Control) string {
	if bindings := g.configSettingBindings(control.ID); len(bindings) > 0 {
		return g.configValue(bindings[0].control, bindings[0].setting)
	}
	if value, ok := g.state.FieldValues[control.ID]; ok {
		return value
	}
	return control.Value
}

func (g *GioApp) configValue(control bundle.Control, setting bundle.ConfigSetting) string {
	g.syncConfigFromWidgets()
	if value, ok := g.configValues[configValueKey(control, setting)]; ok {
		return value
	}
	return setting.Value
}

func (g *GioApp) syncConfigFromWidgets() {
	for _, control := range g.configEditorControls() {
		for _, setting := range control.Settings {
			key := configValueKey(control, setting)
			switch setting.Kind {
			case "dropdown":
				if dropdown := g.dropdowns[setting.ID]; dropdown != nil && len(dropdown.options) > 0 {
					g.configValues[key] = dropdown.options[dropdown.index].ID
				}
			case "toggle":
				if toggle := g.toggles[setting.ID]; toggle != nil {
					g.configValues[key] = strconv.FormatBool(toggle.Value)
				}
			default:
				if editor := g.textFields[setting.ID]; editor != nil {
					g.configValues[key] = editor.Text()
				}
			}
		}
	}
}

func (g *GioApp) syncSharedFieldsFromConfig(control bundle.Control) {
	for _, setting := range control.Settings {
		value := g.configValues[configValueKey(control, setting)]
		for _, id := range []string{setting.ID, setting.Key} {
			if editor := g.textFields[id]; editor != nil {
				editor.SetText(value)
			}
			if dropdown := g.dropdowns[id]; dropdown != nil {
				dropdown.index = selectedOptionIndex(dropdown.options, value)
			}
			if toggle := g.toggles[id]; toggle != nil {
				toggle.Value = value == "true"
			}
		}
	}
}

func (g *GioApp) configEditorControls() []bundle.Control {
	controls := []bundle.Control{}
	for _, page := range g.bundle.Manifest.Pages {
		for _, section := range page.Sections {
			for _, control := range section.Controls {
				if control.Kind == "configEditor" {
					controls = append(controls, control)
				}
			}
		}
	}
	return controls
}

func (g *GioApp) configSettingBindings(fieldID string) []configBinding {
	bindings := []configBinding{}
	for _, control := range g.configEditorControls() {
		for _, setting := range control.Settings {
			if setting.ID == fieldID || setting.Key == fieldID {
				bindings = append(bindings, configBinding{control: control, setting: setting})
			}
		}
	}
	return bindings
}

func configValueKey(control bundle.Control, setting bundle.ConfigSetting) string {
	return control.ID + "." + setting.ID
}

func parseFlatTomlFile(path string) (map[string]string, error) {
	bytes, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	values := map[string]string{}
	for lineNumber, rawLine := range strings.Split(string(bytes), "\n") {
		line := strings.TrimSpace(rawLine)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		index := assignmentSeparator(line)
		if index < 0 {
			return nil, fmt.Errorf("%s:%d: expected key=value", path, lineNumber+1)
		}
		rawKey := strings.TrimSpace(line[:index])
		rawValue := strings.TrimSpace(line[index+1:])
		key, err := parseTomlScalar(rawKey)
		if err != nil {
			return nil, err
		}
		value, err := parseTomlScalar(rawValue)
		if err != nil {
			return nil, err
		}
		values[key] = value
	}
	return values, nil
}

func writeFlatTomlFile(path string, values map[string]string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	var builder strings.Builder
	for _, key := range keys {
		builder.WriteString(tomlKey(key))
		builder.WriteString(" = ")
		builder.WriteString(strconv.Quote(values[key]))
		builder.WriteByte('\n')
	}
	return os.WriteFile(path, []byte(builder.String()), 0o644)
}

func assignmentSeparator(line string) int {
	inQuotes := false
	escaped := false
	for index, r := range line {
		if escaped {
			escaped = false
			continue
		}
		if r == '\\' && inQuotes {
			escaped = true
			continue
		}
		if r == '"' {
			inQuotes = !inQuotes
			continue
		}
		if r == '=' && !inQuotes {
			return index
		}
	}
	return -1
}

func parseTomlScalar(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if strings.HasPrefix(trimmed, "\"") {
		return strconv.Unquote(trimmed)
	}
	if index := strings.Index(trimmed, " #"); index >= 0 {
		trimmed = strings.TrimSpace(trimmed[:index])
	}
	return trimmed, nil
}

func tomlKey(key string) string {
	if key == "" {
		return strconv.Quote(key)
	}
	for _, r := range key {
		if !(r == '_' || r == '-' || r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z' || r >= '0' && r <= '9') {
			return strconv.Quote(key)
		}
	}
	return key
}
