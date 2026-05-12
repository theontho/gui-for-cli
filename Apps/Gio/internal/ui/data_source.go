package ui

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

const dataSourceTimeout = 15 * time.Second

type dataSourcePayload struct {
	Values     map[string]string `json:"values"`
	Options    []bundle.Option   `json:"options"`
	Rows       []bundle.ListRow  `json:"rows"`
	Items      []bundle.ListItem `json:"items"`
	RowActions []bundle.Action   `json:"rowActions"`
	Actions    []bundle.Action   `json:"actions"`
}

func (g *GioApp) refreshDataSources() error {
	return g.refreshDataSourcesForPage(g.activePageID)
}

func (g *GioApp) refreshDataSourcesForPage(pageID string) error {
	g.syncConfigFromWidgets()
	var firstErr error
	for pageIndex := range g.bundle.Manifest.Pages {
		page := &g.bundle.Manifest.Pages[pageIndex]
		if page.ID != pageID {
			continue
		}
		for sectionIndex := range page.Sections {
			section := &page.Sections[sectionIndex]
			if section.DataSource != nil {
				key := "section:" + section.ID
				payload, err := g.runDataSource(*section.DataSource, nil)
				if err != nil {
					g.dataSourceErrors[key] = err.Error()
					if firstErr == nil {
						firstErr = err
					}
				} else {
					delete(g.dataSourceErrors, key)
					g.sectionValues[section.ID] = payload.Values
				}
			}
			for controlIndex := range section.Controls {
				control := &section.Controls[controlIndex]
				if control.DataSource != nil {
					key := "control:" + control.ID
					payload, err := g.runDataSource(*control.DataSource, nil)
					if err != nil {
						g.dataSourceErrors[key] = err.Error()
						if firstErr == nil {
							firstErr = err
						}
					} else {
						delete(g.dataSourceErrors, key)
						applyPayloadToControl(control, payload)
					}
				}
				for settingIndex := range control.Settings {
					setting := &control.Settings[settingIndex]
					if setting.DataSource == nil {
						continue
					}
					key := "setting:" + control.ID + "." + setting.ID
					payload, err := g.runDataSource(*setting.DataSource, nil)
					if err != nil {
						g.dataSourceErrors[key] = err.Error()
						if firstErr == nil {
							firstErr = err
						}
					} else if len(payload.Options) > 0 {
						delete(g.dataSourceErrors, key)
						setting.Options = payload.Options
					}
				}
			}
		}
	}
	return firstErr
}

func applyPayloadToControl(control *bundle.Control, payload dataSourcePayload) {
	if len(payload.Options) > 0 {
		control.Options = payload.Options
	}
	if len(payload.Rows) > 0 {
		control.Rows = payload.Rows
		control.Items = nil
	}
	if len(payload.Items) > 0 {
		control.Items = payload.Items
	}
	if len(payload.RowActions) > 0 {
		control.RowActions = payload.RowActions
	} else if len(payload.Actions) > 0 {
		control.RowActions = payload.Actions
	}
}

func (g *GioApp) runDataSource(dataSource bundle.ScriptDataSource, rowValues map[string]string) (dataSourcePayload, error) {
	if strings.TrimSpace(dataSource.Path) == "" {
		return dataSourcePayload{}, fmt.Errorf("missing data source path")
	}
	executable, err := g.resolveBundlePath(dataSource.Path)
	if err != nil {
		return dataSourcePayload{}, err
	}
	ctxValues := g.contextValues(rowValues)
	args := interpolateAll(dataSource.Args, ctxValues)
	ctx, cancel := context.WithTimeout(context.Background(), dataSourceTimeout)
	defer cancel()
	command := exec.CommandContext(ctx, executable, args...)
	command.Dir = g.bundle.BundleRoot
	if dataSource.WorkingDirectory != "" {
		command.Dir, err = g.resolveBundlePath(dataSource.WorkingDirectory)
		if err != nil {
			return dataSourcePayload{}, err
		}
	}
	command.Env = append(os.Environ(), g.environment(ctxValues, dataSource.Env)...)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	if err := command.Run(); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return dataSourcePayload{}, fmt.Errorf("data source %s timed out after %.0fs", dataSource.Path, dataSourceTimeout.Seconds())
		}
		return dataSourcePayload{}, fmt.Errorf("data source %s failed: %w: %s", dataSource.Path, err, strings.TrimSpace(stderr.String()))
	}
	var payload dataSourcePayload
	if err := json.Unmarshal(stdout.Bytes(), &payload); err != nil {
		return dataSourcePayload{}, fmt.Errorf("data source %s did not print valid JSON: %w", dataSource.Path, err)
	}
	return payload, nil
}

func (g *GioApp) contextValues(rowValues map[string]string) map[string]string {
	values := map[string]string{
		"bundleRoot":      g.bundle.BundleRoot,
		"bundleWorkspace": g.bundle.BundleWorkspaceRoot,
		"home":            userHomeDir(),
	}
	for sectionID, sectionValues := range g.sectionValues {
		for key, value := range sectionValues {
			values[key] = value
			values[sectionID+"."+key] = value
		}
	}
	for key, editor := range g.textFields {
		values[key] = editor.Text()
	}
	for key, dropdown := range g.dropdowns {
		if len(dropdown.options) == 0 {
			continue
		}
		values[key] = dropdown.options[dropdown.index].ID
	}
	for key, toggle := range g.toggles {
		values[key] = strconv.FormatBool(toggle.Value)
	}
	for key, group := range g.checkboxGroups {
		values[key] = strings.Join(sortedSelectedIDs(group), ",")
	}
	g.syncConfigFromWidgets()
	for _, control := range g.configEditorControls() {
		for _, setting := range control.Settings {
			value := g.configValues[configValueKey(control, setting)]
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

func (g *GioApp) environment(values map[string]string, overrides map[string]string) []string {
	env := []string{
		"GUI_FOR_CLI_BUNDLE_ROOT=" + g.bundle.BundleRoot,
		"GUI_FOR_CLI_BUNDLE_WORKSPACE=" + g.bundle.BundleWorkspaceRoot,
	}
	for key, value := range values {
		if safeEnvironmentKey(key) != "" {
			env = append(env, "GUI_FOR_CLI_FIELD_"+safeEnvironmentKey(key)+"="+value)
		}
	}
	for _, control := range g.configEditorControls() {
		for _, setting := range control.Settings {
			value := g.configValues[configValueKey(control, setting)]
			env = append(env, "GUI_FOR_CLI_CONFIG_"+safeEnvironmentKey(setting.Key)+"="+value)
		}
	}
	for key, value := range overrides {
		env = append(env, key+"="+interpolate(value, values))
	}
	return env
}

func safeEnvironmentKey(key string) string {
	key = strings.ToUpper(key)
	var builder strings.Builder
	for _, r := range key {
		if r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' {
			builder.WriteRune(r)
		} else {
			builder.WriteByte('_')
		}
	}
	return strings.Trim(builder.String(), "_")
}

func (g *GioApp) resolvePathTokens(value string, configPath string) string {
	output := strings.TrimSpace(value)
	output = strings.ReplaceAll(output, "{{bundleRoot}}", g.bundle.BundleRoot)
	output = strings.ReplaceAll(output, "{{bundleWorkspace}}", g.bundle.BundleWorkspaceRoot)
	output = strings.ReplaceAll(output, "{{bundleRootBasename}}", filepath.Base(g.bundle.BundleRoot))
	output = strings.ReplaceAll(output, "{{home}}", userHomeDir())
	output = strings.ReplaceAll(output, "{{configHome}}", g.bundle.BundleWorkspaceRoot)
	output = strings.ReplaceAll(output, "{{userConfig}}", g.bundle.BundleWorkspaceRoot)
	output = strings.ReplaceAll(output, "{{applicationSupport}}", g.bundle.BundleWorkspaceRoot)
	output = strings.ReplaceAll(output, "{{appConfig}}", g.bundle.BundleWorkspaceRoot)
	output = strings.ReplaceAll(output, "{{configPath}}", configPath)
	configDir := ""
	if configPath != "" {
		configDir = filepath.Dir(configPath)
	}
	output = strings.ReplaceAll(output, "{{configDir}}", configDir)
	if strings.HasPrefix(output, "~/") || output == "~" {
		output = filepath.Join(userHomeDir(), strings.TrimPrefix(output, "~"))
	}
	if filepath.IsAbs(output) {
		return filepath.Clean(output)
	}
	return filepath.Clean(filepath.Join(g.bundle.BundleRoot, output))
}

func (g *GioApp) resolveBundlePath(value string) (string, error) {
	expanded := g.resolvePathTokens(value, "")
	if !strings.HasPrefix(expanded, g.bundle.BundleRoot+string(filepath.Separator)) && expanded != g.bundle.BundleRoot {
		return "", fmt.Errorf("bundle script path escapes bundle root: %s", value)
	}
	return expanded, nil
}

func computedFileStateValues(values map[string]string) map[string]string {
	computed := map[string]string{}
	for id, rawPath := range values {
		if strings.Contains(id, ".") || strings.TrimSpace(rawPath) == "" {
			continue
		}
		path := expandUserPath(rawPath)
		computed[id+".pathExtension"] = strings.TrimPrefix(strings.ToLower(filepath.Ext(path)), ".")
		computed[id+".parentDir"] = filepath.Dir(path)
		computed[id+".exists"] = strconv.FormatBool(pathExists(path))
		computed[id+".isIndexed"] = strconv.FormatBool(isIndexedAlignment(path))
		computed[id+".isSorted"] = strconv.FormatBool(isSortedAlignment(path))
		if info, err := os.Stat(path); err == nil && info.Mode().IsRegular() {
			computed[id+".fileSize"] = strconv.FormatInt(info.Size(), 10)
			computed[id+".fileSizeGB"] = strconv.FormatFloat(float64(info.Size())/1_073_741_824.0, 'f', 2, 64)
		} else {
			computed[id+".fileSize"] = ""
			computed[id+".fileSizeGB"] = ""
		}
	}
	return computed
}

func expandUserPath(path string) string {
	if strings.HasPrefix(path, "~/") || path == "~" {
		return filepath.Join(userHomeDir(), strings.TrimPrefix(path, "~"))
	}
	return path
}

func isIndexedAlignment(path string) bool {
	ext := filepath.Ext(path)
	withoutExt := strings.TrimSuffix(path, ext)
	candidates := []string{
		path + ".bai",
		path + ".crai",
		path + ".csi",
		withoutExt + ".bai",
		withoutExt + ".crai",
		withoutExt + ".csi",
	}
	for _, candidate := range candidates {
		if pathExists(candidate) {
			return true
		}
	}
	return false
}

func isSortedAlignment(path string) bool {
	if isIndexedAlignment(path) {
		return true
	}
	name := strings.ToLower(filepath.Base(path))
	return strings.Contains(name, ".sorted.") ||
		strings.Contains(name, "_sorted.") ||
		strings.HasSuffix(name, ".sorted.bam") ||
		strings.HasSuffix(name, ".sorted.cram") ||
		strings.Contains(name, ".sort.") ||
		strings.Contains(name, "_sort.")
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func userHomeDir() string {
	if home, err := os.UserHomeDir(); err == nil {
		return home
	}
	return ""
}

func interpolateAll(values []string, context map[string]string) []string {
	rendered := make([]string, 0, len(values))
	for _, value := range values {
		rendered = append(rendered, interpolate(value, context))
	}
	return rendered
}

func interpolate(value string, context map[string]string) string {
	return placeholderPattern.ReplaceAllStringFunc(value, func(match string) string {
		parts := placeholderPattern.FindStringSubmatch(match)
		if len(parts) < 2 {
			return match
		}
		return context[strings.TrimSpace(parts[1])]
	})
}

func missingPlaceholders(values []string, context map[string]string) []string {
	seen := map[string]struct{}{}
	missing := []string{}
	for _, value := range values {
		for _, placeholder := range extractPlaceholders(value) {
			if _, ok := seen[placeholder]; ok {
				continue
			}
			seen[placeholder] = struct{}{}
			if strings.TrimSpace(context[placeholder]) == "" {
				missing = append(missing, placeholder)
			}
		}
	}
	sort.Strings(missing)
	return missing
}

func extractPlaceholders(value string) []string {
	matches := placeholderPattern.FindAllStringSubmatch(value, -1)
	placeholders := make([]string, 0, len(matches))
	for _, match := range matches {
		placeholders = append(placeholders, strings.TrimSpace(match[1]))
	}
	return placeholders
}
