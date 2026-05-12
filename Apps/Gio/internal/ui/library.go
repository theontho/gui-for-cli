package ui

import (
	"fmt"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

func (g *GioApp) layoutLibraryList(gtx layout.Context, control bundle.Control) layout.Dimensions {
	rows := hydrateRows(control)
	children := []layout.FlexChild{
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body1(g.theme, control.Label).Layout(gtx)
		}),
	}
	if errText := g.dataSourceErrors["control:"+control.ID]; errText != "" {
		key := "control:" + control.ID
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return g.layoutDataSourceError(gtx, key, errText)
		}))
	}
	if len(rows) == 0 {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return mutedText(g.theme, g.stringLabel("app.library.empty", "No library items are defined.")).Layout(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	}
	children = append(children,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return mutedText(g.theme, libraryHeader(control)).Layout(gtx)
		}),
	)
	maxRows := len(rows)
	if maxRows > 80 {
		maxRows = 80
	}
	for index := 0; index < maxRows; index++ {
		row := rows[index]
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return g.layoutLibraryRow(gtx, control, row)
		}))
	}
	if len(rows) > maxRows {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return mutedText(g.theme, fmt.Sprintf("Showing %d of %d rows", maxRows, len(rows))).Layout(gtx)
		}))
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (g *GioApp) layoutLibraryRow(gtx layout.Context, control bundle.Control, row bundle.ListRow) layout.Dimensions {
	rowValues := rowContext(row)
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body2(g.theme, rowText(control, row)).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return g.layoutActions(gtx, control.RowActions, rowValues, "row:"+control.ID+":"+row.ID)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(6)}.Layout(gtx)
		}),
	)
}

func hydrateRows(control bundle.Control) []bundle.ListRow {
	if len(control.Items) == 0 {
		return control.Rows
	}
	template := control.RowTemplate
	if template == nil {
		values := map[string]string{}
		for _, column := range control.Columns {
			values[column.ID] = "{{" + column.ID + "}}"
		}
		template = &bundle.ListRow{
			ID:     "{{id}}",
			Title:  "{{name}}",
			Values: values,
			Status: "{{status}}",
		}
	}
	rows := make([]bundle.ListRow, 0, len(control.Items))
	for index, item := range control.Items {
		values := item.Values
		fallbackID := values["id"]
		if fallbackID == "" {
			fallbackID = fmt.Sprintf("row-%d", index+1)
		}
		row := bundle.ListRow{
			ID:      nonEmpty(interpolateItem(template.ID, values), fallbackID),
			Title:   nonEmpty(interpolateItem(template.Title, values), values["title"]),
			Status:  nonEmpty(interpolateItem(template.Status, values), values["status"]),
			Tooltip: nonEmpty(interpolateItem(template.Tooltip, values), values["tooltip"]),
			Values:  map[string]string{},
			Tags:    mergeTags(interpolateTags(template.Tags, values), tagsFromItem(values)),
		}
		if row.Title == "" {
			row.Title = row.ID
		}
		for key, value := range template.Values {
			row.Values[key] = interpolateItem(value, values)
		}
		for key, value := range values {
			if _, ok := row.Values[key]; !ok {
				row.Values[key] = value
			}
		}
		rows = append(rows, row)
	}
	return rows
}

func libraryHeader(control bundle.Control) string {
	titles := make([]string, 0, len(control.Columns)+1)
	for _, column := range control.Columns {
		titles = append(titles, column.Title)
	}
	if len(control.RowActions) > 0 {
		titles = append(titles, "Actions")
	}
	return strings.Join(titles, " | ")
}

func rowText(control bundle.Control, row bundle.ListRow) string {
	parts := make([]string, 0, len(control.Columns))
	for _, column := range control.Columns {
		value := row.Values[column.ID]
		if column.ID == "name" && row.Title != "" {
			value = row.Title
		}
		if column.ID == "status" && row.Status != "" {
			value = row.Status
		}
		parts = append(parts, value)
	}
	if row.Status != "" {
		parts = append(parts, "["+row.Status+"]")
	}
	for _, tag := range row.Tags {
		parts = append(parts, "#"+tag.Title)
	}
	return strings.Join(parts, " | ")
}

func rowContext(row bundle.ListRow) map[string]string {
	values := map[string]string{
		"id":    row.ID,
		"title": row.Title,
	}
	for key, value := range row.Values {
		values[key] = value
	}
	if row.Status != "" {
		values["status"] = row.Status
	}
	return values
}

func interpolateItem(value string, values map[string]string) string {
	return placeholderPattern.ReplaceAllStringFunc(value, func(match string) string {
		parts := placeholderPattern.FindStringSubmatch(match)
		if len(parts) < 2 {
			return match
		}
		placeholder := strings.TrimSpace(parts[1])
		placeholder = strings.TrimPrefix(placeholder, "item.")
		return values[placeholder]
	})
}

func interpolateTags(tags []bundle.Tag, values map[string]string) []bundle.Tag {
	rendered := make([]bundle.Tag, 0, len(tags))
	for _, tag := range tags {
		tag.ID = interpolateItem(tag.ID, values)
		tag.Title = interpolateItem(tag.Title, values)
		if strings.TrimSpace(tag.Title) != "" {
			rendered = append(rendered, tag)
		}
	}
	return rendered
}

func tagsFromItem(values map[string]string) []bundle.Tag {
	if values["tag"] == "" {
		return nil
	}
	return []bundle.Tag{{ID: values["tag"], Title: values["tag"], Style: "secondary"}}
}

func mergeTags(first []bundle.Tag, second []bundle.Tag) []bundle.Tag {
	seen := map[string]struct{}{}
	merged := []bundle.Tag{}
	for _, tag := range append(first, second...) {
		key := tag.ID + "\x00" + tag.Title
		if strings.TrimSpace(tag.Title) == "" {
			continue
		}
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		merged = append(merged, tag)
	}
	return merged
}

func nonEmpty(primary string, fallback string) string {
	if strings.TrimSpace(primary) != "" {
		return primary
	}
	return fallback
}
