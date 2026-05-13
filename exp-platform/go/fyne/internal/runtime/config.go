package runtime

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/theontho/gui-for-cli/apps/fyne/internal/bundle"
)

func (m *Model) initConfigPaths() {
	if m.State.ConfigFilePaths == nil {
		m.State.ConfigFilePaths = map[string]string{}
	}
	for _, control := range ConfigEditorControls(m.Bundle.Manifest) {
		if control.ConfigFile == nil {
			continue
		}
		path := control.ConfigFile.Path
		if persisted := strings.TrimSpace(m.State.ConfigFilePaths[control.ID]); persisted != "" {
			path = persisted
		}
		m.State.ConfigFilePaths[control.ID] = m.ResolvePathTokens(path, "")
	}
}

func (m *Model) LoadInitialConfigs() error {
	var firstErr error
	for _, control := range ConfigEditorControls(m.Bundle.Manifest) {
		if err := m.BootstrapConfigIfNeeded(control); err != nil && firstErr == nil {
			firstErr = err
		}
		if err := m.LoadConfig(control); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

func (m *Model) BootstrapConfigIfNeeded(control bundle.Control) error {
	if control.ConfigFile == nil || control.ConfigFile.Bootstrap == nil || control.ConfigFile.Bootstrap.Script == nil {
		return nil
	}
	path := m.State.ConfigFilePaths[control.ID]
	if _, err := os.Stat(path); err == nil {
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if control.ConfigFile.Bootstrap.Mode != "" && control.ConfigFile.Bootstrap.Mode != "createIfMissing" {
		return nil
	}
	script := control.ConfigFile.Bootstrap.Script
	executable, err := m.ResolveBundlePath(script.Path)
	if err != nil {
		return err
	}
	context := m.Context(map[string]string{"configPath": path, "configDir": filepath.Dir(path)})
	command := exec.Command(executable, InterpolateAll(script.Args, context)...)
	command.Dir = m.Bundle.BundleRoot
	if script.WorkingDirectory != "" {
		command.Dir, err = m.ResolveBundlePath(script.WorkingDirectory)
		if err != nil {
			return err
		}
	}
	command.Env = append(os.Environ(), m.Environment(context, script.Env)...)
	output, err := command.CombinedOutput()
	if err != nil {
		return fmt.Errorf("bootstrap config %s: %w: %s", control.ID, err, strings.TrimSpace(string(output)))
	}
	return nil
}

func (m *Model) LoadConfig(control bundle.Control) error {
	if control.ConfigFile == nil {
		return nil
	}
	path := m.ResolvePathTokens(m.State.ConfigFilePaths[control.ID], "")
	if strings.TrimSpace(path) == "" {
		return fmt.Errorf("choose a settings file path before loading %s", control.Label)
	}
	m.State.ConfigFilePaths[control.ID] = path
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
		m.ConfigValues[ConfigValueKey(control, setting)] = value
		if setting.ID != "" {
			m.State.FieldValues[setting.ID] = value
		}
	}
	return m.SaveState()
}

func (m *Model) SaveConfig(control bundle.Control) error {
	if control.ConfigFile == nil {
		return nil
	}
	path := m.ResolvePathTokens(m.State.ConfigFilePaths[control.ID], "")
	if strings.TrimSpace(path) == "" {
		return fmt.Errorf("choose a settings file path before saving %s", control.Label)
	}
	values := map[string]string{}
	for _, setting := range control.Settings {
		values[setting.Key] = m.ConfigValues[ConfigValueKey(control, setting)]
	}
	if err := writeFlatTomlFile(path, values); err != nil {
		return err
	}
	m.State.ConfigFilePaths[control.ID] = path
	return m.SaveState()
}

func (m *Model) ResolveBundlePath(value string) (string, error) {
	resolved := m.ResolvePathTokens(value, "")
	if filepath.IsAbs(resolved) {
		return resolved, nil
	}
	return filepath.Join(m.Bundle.BundleRoot, resolved), nil
}

func (m *Model) ResolvePathTokens(value string, configPath string) string {
	output := strings.TrimSpace(value)
	output = strings.ReplaceAll(output, "{{bundleRoot}}", m.Bundle.BundleRoot)
	output = strings.ReplaceAll(output, "{{bundleWorkspace}}", m.Bundle.BundleWorkspaceRoot)
	output = strings.ReplaceAll(output, "{{bundleRootBasename}}", filepath.Base(m.Bundle.BundleRoot))
	output = strings.ReplaceAll(output, "{{home}}", userHomeDir())
	if configPath != "" {
		output = strings.ReplaceAll(output, "{{configPath}}", configPath)
		output = strings.ReplaceAll(output, "{{configDir}}", filepath.Dir(configPath))
	}
	return output
}

func parseFlatTomlFile(path string) (map[string]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	values := map[string]string{}
	scanner := bufio.NewScanner(file)
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "[") {
			continue
		}
		index := strings.Index(line, "=")
		if index < 0 {
			return nil, fmt.Errorf("%s:%d expected key=value", path, lineNumber)
		}
		key := strings.Trim(strings.TrimSpace(line[:index]), `"`)
		valueText := strings.TrimSpace(line[index+1:])
		if comment := strings.Index(valueText, " #"); comment >= 0 {
			valueText = strings.TrimSpace(valueText[:comment])
		}
		if unquoted, err := strconv.Unquote(valueText); err == nil {
			values[key] = unquoted
		} else {
			values[key] = strings.Trim(valueText, `"`)
		}
	}
	return values, scanner.Err()
}

func writeFlatTomlFile(path string, values map[string]string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	var builder strings.Builder
	for key, value := range values {
		builder.WriteString(key)
		builder.WriteString(" = ")
		builder.WriteString(strconv.Quote(value))
		builder.WriteByte('\n')
	}
	return os.WriteFile(path, []byte(builder.String()), 0o644)
}
