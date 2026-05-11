package ui

import (
	"math"
	"testing"

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
