package ui

import (
	"testing"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

func TestHydrateRowsUsesItemsAndTemplate(t *testing.T) {
	control := bundle.Control{
		Columns: []bundle.ListColumn{
			{ID: "name", Title: "Name"},
			{ID: "build", Title: "Build"},
		},
		Items: []bundle.ListItem{
			{Values: map[string]string{"id": "hg38", "name": "Human GRCh38", "build": "GRCh38", "status": "missing"}},
		},
		RowTemplate: &bundle.ListRow{
			ID:     "{{id}}",
			Title:  "{{name}}",
			Status: "{{status}}",
			Values: map[string]string{
				"name":  "{{name}}",
				"build": "{{build}}",
			},
			Tags: []bundle.Tag{{ID: "build", Title: "{{build}}", Style: "primary"}},
		},
	}
	rows := hydrateRows(control)
	if len(rows) != 1 {
		t.Fatalf("got %d rows, want 1", len(rows))
	}
	row := rows[0]
	if row.ID != "hg38" || row.Title != "Human GRCh38" || row.Status != "missing" {
		t.Fatalf("unexpected row identity: %#v", row)
	}
	if row.Values["build"] != "GRCh38" {
		t.Fatalf("build value = %q", row.Values["build"])
	}
	if len(row.Tags) != 1 || row.Tags[0].Title != "GRCh38" {
		t.Fatalf("tags = %#v", row.Tags)
	}
}
