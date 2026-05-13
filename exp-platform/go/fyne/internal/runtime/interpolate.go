package runtime

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/theontho/gui-for-cli/apps/fyne/internal/bundle"
)

var placeholderPattern = regexp.MustCompile(`\{\{([^{}]+)\}\}`)

func Interpolate(value string, context map[string]string) string {
	return placeholderPattern.ReplaceAllStringFunc(value, func(match string) string {
		parts := placeholderPattern.FindStringSubmatch(match)
		if len(parts) != 2 {
			return ""
		}
		return context[strings.TrimSpace(parts[1])]
	})
}

func InterpolateAll(values []string, context map[string]string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		out = append(out, Interpolate(value, context))
	}
	return out
}

func PlaceholdersIn(values []string) []string {
	seen := map[string]bool{}
	var placeholders []string
	for _, value := range values {
		for _, match := range placeholderPattern.FindAllStringSubmatch(value, -1) {
			placeholder := strings.TrimSpace(match[1])
			if placeholder != "" && !seen[placeholder] {
				seen[placeholder] = true
				placeholders = append(placeholders, placeholder)
			}
		}
	}
	return placeholders
}

func MissingPlaceholders(command bundle.Command, context map[string]string) []string {
	values := append([]string{command.Executable}, command.Arguments...)
	missing := []string{}
	for _, placeholder := range PlaceholdersIn(values) {
		if strings.TrimSpace(context[placeholder]) == "" {
			missing = append(missing, placeholder)
		}
	}
	return missing
}

func RenderCommand(command bundle.Command, context map[string]string) (string, []string, []string) {
	missing := MissingPlaceholders(command, context)
	if len(missing) > 0 {
		return "", nil, missing
	}
	args := InterpolateAll(command.Arguments, context)
	for _, group := range command.OptionalArguments {
		if len(missingRequiredPlaceholders(group, context)) == 0 {
			args = append(args, InterpolateAll(group, context)...)
		}
	}
	return Interpolate(command.Executable, context), args, nil
}

func DisplayCommand(executable string, args []string) string {
	quoted := append([]string{shellQuote(executable)}, quoteAll(args)...)
	return strings.Join(quoted, " ")
}

func ActionVisible(action bundle.Action, context map[string]string) bool {
	for _, condition := range action.VisibleWhen {
		if !ConditionMatches(condition, context) {
			return false
		}
	}
	return true
}

func DisabledReason(action bundle.Action, context map[string]string, fallback string) string {
	for _, condition := range action.DisabledWhen {
		if ConditionMatches(condition, context) {
			if action.DisabledTooltip != "" {
				return Interpolate(action.DisabledTooltip, context)
			}
			return fallback
		}
	}
	return ""
}

func ConditionMatches(condition bundle.ActionCondition, context map[string]string) bool {
	value := strings.TrimSpace(context[condition.Placeholder])
	if condition.Exists != nil && *condition.Exists != (value != "") {
		return false
	}
	if condition.Equals != "" && value != Interpolate(condition.Equals, context) {
		return false
	}
	if condition.NotEquals != "" && value == Interpolate(condition.NotEquals, context) {
		return false
	}
	if len(condition.In) > 0 && !contains(value, InterpolateAll(condition.In, context)) {
		return false
	}
	if len(condition.NotIn) > 0 && contains(value, InterpolateAll(condition.NotIn, context)) {
		return false
	}
	comparisons := []struct {
		right string
		fn    func(float64, float64) bool
	}{
		{condition.LessThan, func(l, r float64) bool { return l < r }},
		{condition.LessThanOrEqual, func(l, r float64) bool { return l <= r }},
		{condition.GreaterThan, func(l, r float64) bool { return l > r }},
		{condition.GreaterThanOrEqual, func(l, r float64) bool { return l >= r }},
	}
	for _, comparison := range comparisons {
		if comparison.right != "" && !compareNumeric(value, Interpolate(comparison.right, context), comparison.fn) {
			return false
		}
	}
	return true
}

func HydrateRows(control bundle.Control) []bundle.ListRow {
	if len(control.Items) == 0 {
		return control.Rows
	}
	template := control.RowTemplate
	if template == nil {
		template = &bundle.ListRow{ID: "{{id}}", Title: "{{name}}", Status: "{{status}}", Values: map[string]string{}}
		for _, column := range control.Columns {
			template.Values[column.ID] = "{{" + column.ID + "}}"
		}
	}
	rows := make([]bundle.ListRow, 0, len(control.Items))
	for index, item := range control.Items {
		values := map[string]string{}
		for key, value := range item.Values {
			values[key] = value
		}
		fallbackID := values["id"]
		if fallbackID == "" {
			fallbackID = fmt.Sprintf("row-%d", index+1)
		}
		row := bundle.ListRow{
			ID:      nonEmpty(Interpolate(template.ID, values), fallbackID),
			Title:   nonEmpty(Interpolate(template.Title, values), values["title"]),
			Status:  nonEmpty(Interpolate(template.Status, values), values["status"]),
			Tooltip: nonEmpty(Interpolate(template.Tooltip, values), values["tooltip"]),
			Values:  map[string]string{},
			Tags:    mergeTags(interpolateTags(template.Tags, values), nil),
		}
		for key, value := range template.Values {
			row.Values[key] = Interpolate(value, values)
		}
		rows = append(rows, row)
	}
	return rows
}

func RowContext(base map[string]string, row bundle.ListRow) map[string]string {
	context := cloneMap(base)
	rowValues := cloneMap(row.Values)
	rowValues["id"] = row.ID
	if row.Title != "" {
		rowValues["title"] = row.Title
	}
	if row.Status != "" {
		rowValues["status"] = row.Status
	}
	for key, value := range rowValues {
		context[key] = value
		context["row."+key] = value
	}
	return context
}

func missingRequiredPlaceholders(values []string, context map[string]string) []string {
	missing := []string{}
	for _, placeholder := range PlaceholdersIn(values) {
		if strings.TrimSpace(context[placeholder]) == "" {
			missing = append(missing, placeholder)
		}
	}
	return missing
}

func quoteAll(values []string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		out = append(out, shellQuote(value))
	}
	return out
}

func shellQuote(value string) string {
	if value == "" {
		return "''"
	}
	if regexp.MustCompile(`^[A-Za-z0-9_./:-]+$`).MatchString(value) {
		return value
	}
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func compareNumeric(left, right string, predicate func(float64, float64) bool) bool {
	leftValue, leftErr := strconv.ParseFloat(strings.TrimSpace(left), 64)
	rightValue, rightErr := strconv.ParseFloat(strings.TrimSpace(right), 64)
	return leftErr == nil && rightErr == nil && predicate(leftValue, rightValue)
}

func contains(value string, values []string) bool {
	for _, candidate := range values {
		if candidate == value {
			return true
		}
	}
	return false
}

func nonEmpty(value string, fallback string) string {
	if strings.TrimSpace(value) != "" {
		return value
	}
	return fallback
}

func interpolateTags(tags []bundle.Tag, values map[string]string) []bundle.Tag {
	out := make([]bundle.Tag, 0, len(tags))
	for _, tag := range tags {
		tag.ID = Interpolate(tag.ID, values)
		tag.Title = Interpolate(tag.Title, values)
		if strings.TrimSpace(tag.Title) != "" {
			out = append(out, tag)
		}
	}
	return out
}

func mergeTags(first []bundle.Tag, second []bundle.Tag) []bundle.Tag {
	seen := map[string]bool{}
	out := []bundle.Tag{}
	for _, tag := range append(first, second...) {
		key := tag.ID + "\x00" + tag.Title
		if tag.Title == "" || seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, tag)
	}
	return out
}

func sortedSelected(values []string) string {
	copyValues := append([]string{}, values...)
	sort.Strings(copyValues)
	return strings.Join(copyValues, ",")
}

func cloneMap(values map[string]string) map[string]string {
	out := map[string]string{}
	for key, value := range values {
		out[key] = value
	}
	return out
}
