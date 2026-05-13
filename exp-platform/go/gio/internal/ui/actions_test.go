package ui

import (
	"image/color"
	"math"
	"testing"

	"gioui.org/widget"
	"gioui.org/widget/material"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

func TestConditionMatchesRichPredicates(t *testing.T) {
	exists := true
	context := map[string]string{
		"row.status": "missing",
		"size":       "12",
	}
	cases := []bundle.ActionCondition{
		{Placeholder: "row.status", Equals: "missing"},
		{Placeholder: "row.status", In: []string{"installed", "missing"}},
		{Placeholder: "size", GreaterThan: "10"},
		{Placeholder: "size", LessThanOrEqual: "12"},
		{Placeholder: "row.status", Exists: &exists},
	}
	for _, condition := range cases {
		if !conditionMatches(condition, context) {
			t.Fatalf("condition did not match: %#v", condition)
		}
	}
	if conditionMatches(bundle.ActionCondition{Placeholder: "row.status", NotEquals: "missing"}, context) {
		t.Fatal("notEquals condition unexpectedly matched")
	}
}

func TestRenderCommandOptionalArguments(t *testing.T) {
	command := bundle.Command{
		Executable: "{{bundleRoot}}/run.sh",
		Arguments:  []string{"--input", "{{input}}"},
		OptionalArguments: [][]string{
			{"--ref", "{{ref}}"},
			{"--out", "{{out}}"},
		},
	}
	executable, args, missing := renderCommand(command, map[string]string{
		"bundleRoot": "/bundle",
		"input":      "sample.bam",
		"out":        "outdir",
	})
	if len(missing) != 0 {
		t.Fatalf("missing = %#v", missing)
	}
	if executable != "/bundle/run.sh" {
		t.Fatalf("executable = %q", executable)
	}
	want := []string{"--input", "sample.bam", "--out", "outdir"}
	for index := range want {
		if args[index] != want[index] {
			t.Fatalf("args = %#v, want %#v", args, want)
		}
	}
	if len(args) != len(want) {
		t.Fatalf("args = %#v, want %#v", args, want)
	}
}

func TestEvaluateNumericExpression(t *testing.T) {
	got := evaluateNumeric("2 + 3 * (4 - 1)")
	if got != 11 {
		t.Fatalf("got %v, want 11", got)
	}
	if !math.IsNaN(evaluateNumeric("2 + nope")) {
		t.Fatal("invalid expression should be NaN")
	}
}

func TestActionButtonStyleUsesDestructiveAndDisabledColors(t *testing.T) {
	app := &GioApp{theme: material.NewTheme(), runningActionKeys: map[string]bool{}}
	app.theme.Palette.Bg = color.NRGBA{R: 255, G: 255, B: 255, A: 255}

	destructive := app.actionButtonStyle(new(widget.Clickable), bundle.Action{Role: "destructive"}, "Delete", false)
	if destructive.Background != destructiveButtonBackground() {
		t.Fatalf("destructive background = %#v, want %#v", destructive.Background, destructiveButtonBackground())
	}

	disabled := app.actionButtonStyle(new(widget.Clickable), bundle.Action{Role: "destructive"}, "Delete", true)
	if disabled.Background == destructiveButtonBackground() {
		t.Fatal("disabled action should use disabled styling instead of destructive red")
	}
}

func TestActionRunningStateTracksByKey(t *testing.T) {
	app := &GioApp{runningActionKeys: map[string]bool{}}
	app.setActionRunning("action:run", true)
	if !app.actionRunning("action:run") {
		t.Fatal("action should be marked running")
	}
	app.setActionRunning("action:run", false)
	if app.actionRunning("action:run") {
		t.Fatal("action should no longer be marked running")
	}
}
