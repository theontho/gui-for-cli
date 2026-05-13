package runtime

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/theontho/gui-for-cli/apps/fyne/internal/bundle"
)

const dataSourceTimeout = 15 * time.Second

type DataSourcePayload struct {
	Values     map[string]string `json:"values"`
	Options    []bundle.Option   `json:"options"`
	Rows       []bundle.ListRow  `json:"rows"`
	Items      []bundle.ListItem `json:"items"`
	RowActions []bundle.Action   `json:"rowActions"`
	Actions    []bundle.Action   `json:"actions"`
}

func (m *Model) RefreshDataSourcesForPage(pageID string) error {
	var firstErr error
	for pageIndex := range m.Bundle.Manifest.Pages {
		page := &m.Bundle.Manifest.Pages[pageIndex]
		if page.ID != pageID {
			continue
		}
		for sectionIndex := range page.Sections {
			section := &page.Sections[sectionIndex]
			if section.DataSource != nil {
				payload, err := m.RunDataSource(*section.DataSource, nil)
				key := "section:" + section.ID
				if err != nil {
					m.DataErrors[key] = err.Error()
					firstErr = first(firstErr, err)
				} else {
					delete(m.DataErrors, key)
					m.SectionValues[section.ID] = payload.Values
				}
			}
			for controlIndex := range section.Controls {
				control := &section.Controls[controlIndex]
				if control.DataSource != nil {
					payload, err := m.RunDataSource(*control.DataSource, nil)
					key := "control:" + control.ID
					if err != nil {
						m.DataErrors[key] = err.Error()
						firstErr = first(firstErr, err)
					} else {
						delete(m.DataErrors, key)
						ApplyPayloadToControl(control, payload)
					}
				}
				for settingIndex := range control.Settings {
					setting := &control.Settings[settingIndex]
					if setting.DataSource == nil {
						continue
					}
					payload, err := m.RunDataSource(*setting.DataSource, nil)
					key := "setting:" + control.ID + "." + setting.ID
					if err != nil {
						m.DataErrors[key] = err.Error()
						firstErr = first(firstErr, err)
					} else if len(payload.Options) > 0 {
						delete(m.DataErrors, key)
						setting.Options = payload.Options
					}
				}
			}
		}
	}
	return firstErr
}

func (m *Model) RunDataSource(dataSource bundle.ScriptDataSource, rowValues map[string]string) (DataSourcePayload, error) {
	if strings.TrimSpace(dataSource.Path) == "" {
		return DataSourcePayload{}, fmt.Errorf("missing data source path")
	}
	executable, err := m.ResolveBundlePath(dataSource.Path)
	if err != nil {
		return DataSourcePayload{}, err
	}
	contextValues := m.Context(rowValues)
	ctx, cancel := context.WithTimeout(context.Background(), dataSourceTimeout)
	defer cancel()
	command := exec.CommandContext(ctx, executable, InterpolateAll(dataSource.Args, contextValues)...)
	command.Dir = m.Bundle.BundleRoot
	if dataSource.WorkingDirectory != "" {
		command.Dir, err = m.ResolveBundlePath(dataSource.WorkingDirectory)
		if err != nil {
			return DataSourcePayload{}, err
		}
	}
	command.Env = append(os.Environ(), m.Environment(contextValues, dataSource.Env)...)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	if err := command.Run(); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return DataSourcePayload{}, fmt.Errorf("data source %s timed out after %.0fs", dataSource.Path, dataSourceTimeout.Seconds())
		}
		return DataSourcePayload{}, fmt.Errorf("data source %s failed: %w: %s", dataSource.Path, err, strings.TrimSpace(stderr.String()))
	}
	var payload DataSourcePayload
	if err := json.Unmarshal(stdout.Bytes(), &payload); err != nil {
		return DataSourcePayload{}, fmt.Errorf("data source %s did not print valid JSON: %w", dataSource.Path, err)
	}
	return payload, nil
}

func ApplyPayloadToControl(control *bundle.Control, payload DataSourcePayload) {
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

func first(existing error, next error) error {
	if existing != nil {
		return existing
	}
	return next
}
