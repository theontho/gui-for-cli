package runtime

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/theontho/gui-for-cli/apps/fyne/internal/bundle"
)

type State struct {
	LocalizationCode string              `json:"localizationCode,omitempty"`
	ConfigFilePaths  map[string]string   `json:"configFilePaths"`
	FieldValues      map[string]string   `json:"fieldValues"`
	CheckedOptions   map[string][]string `json:"checkedOptions"`
	SelectedPageID   string              `json:"selectedPageID,omitempty"`
	SidebarVisible   bool                `json:"fyneSidebarVisible"`
	TerminalVisible  bool                `json:"fyneTerminalVisible"`
}

type Model struct {
	Bundle        *bundle.AppBundle
	State         State
	ConfigValues  map[string]string
	SectionValues map[string]map[string]string
	DataErrors    map[string]string
}

func NewModel(loaded *bundle.AppBundle) *Model {
	model := &Model{
		Bundle:        loaded,
		ConfigValues:  map[string]string{},
		SectionValues: map[string]map[string]string{},
		DataErrors:    map[string]string{},
		State: State{
			ConfigFilePaths: map[string]string{},
			FieldValues:     initialFieldValues(loaded.Manifest),
			CheckedOptions:  initialCheckedOptions(loaded.Manifest),
			SidebarVisible:  true,
			TerminalVisible: true,
		},
	}
	if len(loaded.Manifest.Pages) > 0 {
		model.State.SelectedPageID = loaded.Manifest.Pages[0].ID
	}
	for _, control := range ConfigEditorControls(loaded.Manifest) {
		for _, setting := range control.Settings {
			model.ConfigValues[ConfigValueKey(control, setting)] = setting.Value
		}
	}
	return model
}

func (m *Model) Bootstrap() error {
	if err := os.MkdirAll(m.Bundle.BundleWorkspaceRoot, 0o755); err != nil {
		return err
	}
	loaded, err := LoadState(m.StatePath())
	if err != nil {
		return err
	}
	mergeState(&m.State, loaded)
	m.State.LocalizationCode = m.Bundle.LocalizationCode
	m.initConfigPaths()
	return m.LoadInitialConfigs()
}

func LoadState(path string) (State, error) {
	bytes, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return State{}, nil
		}
		return State{}, fmt.Errorf("load state: %w", err)
	}
	var state State
	if err := json.Unmarshal(bytes, &state); err != nil {
		return State{}, fmt.Errorf("decode state: %w", err)
	}
	return state, nil
}

func (m *Model) SaveState() error {
	if err := os.MkdirAll(m.Bundle.BundleWorkspaceRoot, 0o755); err != nil {
		return err
	}
	bytes, err := json.MarshalIndent(m.State, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(m.StatePath(), append(bytes, '\n'), 0o644)
}

func (m *Model) StatePath() string {
	return filepath.Join(m.Bundle.BundleWorkspaceRoot, "state-fyne.json")
}

func (m *Model) Context(rowValues map[string]string) map[string]string {
	values := map[string]string{
		"bundleRoot":      m.Bundle.BundleRoot,
		"bundleWorkspace": m.Bundle.BundleWorkspaceRoot,
		"home":            userHomeDir(),
	}
	for sectionID, sectionValues := range m.SectionValues {
		for key, value := range sectionValues {
			values[key] = value
			values[sectionID+"."+key] = value
		}
	}
	for key, value := range m.State.FieldValues {
		values[key] = value
	}
	for key, selected := range m.State.CheckedOptions {
		values[key] = sortedSelected(selected)
	}
	for key, value := range m.ConfigValues {
		values[key] = value
	}
	for _, control := range ConfigEditorControls(m.Bundle.Manifest) {
		for _, setting := range control.Settings {
			value := m.ConfigValues[ConfigValueKey(control, setting)]
			values[setting.ID] = value
			values[setting.Key] = value
			values["config."+setting.ID] = value
			values["config."+setting.Key] = value
			values["config."+control.ID+"."+setting.ID] = value
			values["config."+control.ID+"."+setting.Key] = value
		}
	}
	for key, value := range rowValues {
		values[key] = value
		values["row."+key] = value
	}
	for key, value := range computedFileStateValues(values) {
		values[key] = value
	}
	return values
}

func (m *Model) Environment(context map[string]string, overrides map[string]string) []string {
	env := []string{
		"GUI_FOR_CLI_BUNDLE_ROOT=" + m.Bundle.BundleRoot,
		"GUI_FOR_CLI_BUNDLE_WORKSPACE=" + m.Bundle.BundleWorkspaceRoot,
	}
	for key, value := range context {
		if safe := safeEnvironmentKey(key); safe != "" {
			env = append(env, "GUI_FOR_CLI_FIELD_"+safe+"="+value)
		}
	}
	for _, control := range ConfigEditorControls(m.Bundle.Manifest) {
		for _, setting := range control.Settings {
			value := m.ConfigValues[ConfigValueKey(control, setting)]
			env = append(env, "GUI_FOR_CLI_CONFIG_"+safeEnvironmentKey(setting.Key)+"="+value)
		}
	}
	for key, value := range overrides {
		env = append(env, key+"="+Interpolate(value, context))
	}
	return env
}

func AllControls(manifest bundle.Manifest) []bundle.Control {
	controls := []bundle.Control{}
	for _, page := range manifest.Pages {
		for _, section := range page.Sections {
			controls = append(controls, section.Controls...)
		}
	}
	return controls
}

func ConfigEditorControls(manifest bundle.Manifest) []bundle.Control {
	controls := []bundle.Control{}
	for _, control := range AllControls(manifest) {
		if control.Kind == "configEditor" {
			controls = append(controls, control)
		}
	}
	return controls
}

func ConfigValueKey(control bundle.Control, setting bundle.ConfigSetting) string {
	return control.ID + "." + setting.ID
}

func (m *Model) SetField(id string, value string) {
	m.State.FieldValues[id] = value
	_ = m.SaveState()
}

func (m *Model) SetConfig(control bundle.Control, setting bundle.ConfigSetting, value string) {
	m.ConfigValues[ConfigValueKey(control, setting)] = value
	_ = m.SaveConfig(control)
}

func (m *Model) SetChecked(controlID string, optionID string, checked bool) {
	values := map[string]bool{}
	for _, current := range m.State.CheckedOptions[controlID] {
		values[current] = true
	}
	values[optionID] = checked
	selected := []string{}
	for option, isSelected := range values {
		if isSelected {
			selected = append(selected, option)
		}
	}
	m.State.CheckedOptions[controlID] = selected
	_ = m.SaveState()
}

func initialFieldValues(manifest bundle.Manifest) map[string]string {
	values := map[string]string{}
	for _, control := range AllControls(manifest) {
		switch control.Kind {
		case "text", "path", "toggle":
			values[control.ID] = control.Value
		case "dropdown":
			value := control.Value
			if value == "" {
				value = selectedOption(control.Options)
			}
			values[control.ID] = value
		}
	}
	return values
}

func initialCheckedOptions(manifest bundle.Manifest) map[string][]string {
	values := map[string][]string{}
	for _, control := range AllControls(manifest) {
		if control.Kind != "checkboxGroup" {
			continue
		}
		for _, option := range control.Options {
			if option.Selected {
				values[control.ID] = append(values[control.ID], option.ID)
			}
		}
	}
	return values
}

func mergeState(base *State, loaded State) {
	if loaded.ConfigFilePaths != nil {
		base.ConfigFilePaths = loaded.ConfigFilePaths
	}
	if loaded.FieldValues != nil {
		for key, value := range loaded.FieldValues {
			base.FieldValues[key] = value
		}
	}
	if loaded.CheckedOptions != nil {
		base.CheckedOptions = loaded.CheckedOptions
	}
	if loaded.SelectedPageID != "" {
		base.SelectedPageID = loaded.SelectedPageID
	}
	base.LocalizationCode = loaded.LocalizationCode
	base.SidebarVisible = loaded.SidebarVisible || !loaded.TerminalVisible && loaded.ConfigFilePaths == nil
	base.TerminalVisible = loaded.TerminalVisible || !loaded.SidebarVisible && loaded.ConfigFilePaths == nil
	if !base.SidebarVisible && !base.TerminalVisible {
		base.SidebarVisible = true
		base.TerminalVisible = true
	}
}

func selectedOption(options []bundle.Option) string {
	for _, option := range options {
		if option.Selected {
			return option.ID
		}
	}
	if len(options) > 0 {
		return options[0].ID
	}
	return ""
}

func safeEnvironmentKey(key string) string {
	key = strings.ToUpper(key)
	var builder strings.Builder
	for _, char := range key {
		if char >= 'A' && char <= 'Z' || char >= '0' && char <= '9' {
			builder.WriteRune(char)
		} else {
			builder.WriteByte('_')
		}
	}
	return strings.Trim(builder.String(), "_")
}

func computedFileStateValues(values map[string]string) map[string]string {
	computed := map[string]string{}
	for key, value := range values {
		if strings.TrimSpace(value) == "" {
			continue
		}
		if info, err := os.Stat(value); err == nil {
			computed[key+".exists"] = "true"
			computed[key+".isDirectory"] = strconv.FormatBool(info.IsDir())
			computed[key+".fileSize"] = strconv.FormatInt(info.Size(), 10)
			computed[key+".fileSizeGB"] = fmt.Sprintf("%.3f", float64(info.Size())/(1024*1024*1024))
		} else {
			computed[key+".exists"] = "false"
		}
	}
	return computed
}

func userHomeDir() string {
	if home, err := os.UserHomeDir(); err == nil {
		return home
	}
	return ""
}
