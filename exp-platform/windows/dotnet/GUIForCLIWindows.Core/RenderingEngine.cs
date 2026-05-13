using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace GUIForCLIWindows.Core;

public static partial class RenderingEngine
{
    private static readonly Regex PlaceholderPattern = PlaceholderRegex();

    public static IReadOnlyList<ControlSpec> AllControls(BundleManifest manifest) =>
        manifest.Pages.SelectMany(page => page.Sections).SelectMany(section => section.Controls).ToList();

    public static IReadOnlyList<ControlSpec> ConfigEditorControls(BundleManifest manifest) =>
        AllControls(manifest).Where(control => control.Kind == "configEditor").ToList();

    public static string ConfigValueKey(ControlSpec control, ConfigSettingSpec setting) => $"{control.Id}.{setting.Id}";

    public static bool PersistsFieldValue(string kind) => kind is "text" or "path" or "dropdown" or "toggle";

    public static Dictionary<string, string> InitialFieldValues(BundleManifest manifest)
    {
        var values = new Dictionary<string, string>();
        foreach (var control in AllControls(manifest).Where(control => PersistsFieldValue(control.Kind)))
        {
            if (!values.ContainsKey(control.Id) || control.Value is not null)
            {
                values[control.Id] = control.Value ?? "";
            }
        }

        return values;
    }

    public static Dictionary<string, IReadOnlySet<string>> InitialCheckedOptions(BundleManifest manifest) =>
        AllControls(manifest)
            .Where(control => control.Kind == "checkboxGroup")
            .ToDictionary(
                control => control.Id,
                control => (IReadOnlySet<string>)control.Options
                    .Where(option => option.Selected)
                    .Select(option => option.Id)
                    .ToHashSet(StringComparer.Ordinal));

    public static Dictionary<string, string> InitialConfigValues(BundleManifest manifest)
    {
        var values = new Dictionary<string, string>();
        foreach (var control in ConfigEditorControls(manifest))
        {
            foreach (var setting in control.Settings)
            {
                values[ConfigValueKey(control, setting)] = setting.Value ?? "";
            }
        }

        return values;
    }

    public static Dictionary<string, string> CheckedOptionsForContext(IReadOnlyDictionary<string, IReadOnlyCollection<string>> checkedOptions) =>
        checkedOptions.ToDictionary(
            pair => pair.Key,
            pair => string.Join(",", pair.Value.Order(StringComparer.Ordinal)),
            StringComparer.Ordinal);

    public static string? ContextValue(RenderContext context, string placeholder)
    {
        if (placeholder is "bundleRoot" or "bundleWorkspace")
        {
            return context.BundleRootPath;
        }

        if (placeholder == "home")
        {
            return context.HomePath;
        }

        if (placeholder.StartsWith("row.", StringComparison.Ordinal))
        {
            return ValueOrNull(context.RowValues, placeholder[4..]);
        }

        if (placeholder.StartsWith("config.", StringComparison.Ordinal))
        {
            return ValueOrNull(context.ConfigValues, placeholder[7..]);
        }

        var computed = ComputedFileStateValue(context, placeholder);
        if (computed is not null)
        {
            return computed;
        }

        return ValueOrNull(context.RowValues, placeholder)
            ?? ValueOrNull(context.CheckedOptions, placeholder)
            ?? ValueOrNull(context.FieldValues, placeholder)
            ?? ValueOrNull(context.ConfigValues, placeholder);
    }

    public static string Interpolate(string? value, RenderContext context) =>
        PlaceholderPattern.Replace(value ?? "", match =>
        {
            var placeholder = match.Groups[1].Value.Trim();
            return ContextValue(context, placeholder) ?? "";
        });

    public static IReadOnlyList<string> PlaceholdersIn(IEnumerable<string?> values)
    {
        var placeholders = new List<string>();
        foreach (var value in values)
        {
            foreach (Match match in PlaceholderPattern.Matches(value ?? ""))
            {
                var placeholder = match.Groups[1].Value.Trim();
                if (!placeholders.Contains(placeholder, StringComparer.Ordinal))
                {
                    placeholders.Add(placeholder);
                }
            }
        }

        return placeholders;
    }

    public static IReadOnlyList<string> MissingPlaceholders(CommandSpec command, RenderContext context) =>
        PlaceholdersIn(new[] { command.Executable }.Concat(command.Arguments))
            .Where(placeholder => string.IsNullOrWhiteSpace(ContextValue(context, placeholder)))
            .ToList();

    public static RenderedCommand RenderedCommand(CommandSpec command, RenderContext context)
    {
        var optionalArguments = command.OptionalArguments
            .Where(group => MissingRequiredPlaceholders(group, context).Count == 0)
            .SelectMany(group => group.Select(argument => Interpolate(argument, context)))
            .ToList();

        return new RenderedCommand(
            Interpolate(command.Executable, context),
            command.Arguments.Select(argument => Interpolate(argument, context)).Concat(optionalArguments).ToList());
    }

    public static string DisplayCommand(CommandSpec command, RenderContext context)
    {
        var rendered = RenderedCommand(command, context);
        return string.Join(" ", new[] { rendered.Executable }.Concat(rendered.Arguments).Select(ShellQuote));
    }

    public static string ShellQuote(string? value)
    {
        var text = value ?? "";
        return PosixSafeShellTokenRegex().IsMatch(text)
            ? text
            : $"'{text.Replace("'", "'\\''", StringComparison.Ordinal)}'";
    }

    public static bool IsActionVisible(ActionSpec action, RenderContext context) =>
        action.VisibleWhen.All(condition => ConditionMatches(condition, context));

    public static string? DisabledReason(ActionSpec action, RenderContext context, string fallback = "This action is not available.")
    {
        return action.DisabledWhen.Any(condition => ConditionMatches(condition, context))
            ? action.DisabledTooltip is null ? fallback : Interpolate(action.DisabledTooltip, context)
            : null;
    }

    public static bool ConditionMatches(ActionConditionSpec condition, RenderContext context)
    {
        var value = (ContextValue(context, condition.Placeholder) ?? "").Trim();
        if (condition.Exists is not null && condition.Exists.Value != value.Length > 0)
        {
            return false;
        }

        if (condition.EqualTo is not null && value != Interpolate(condition.EqualTo, context))
        {
            return false;
        }

        if (condition.NotEquals is not null && value == Interpolate(condition.NotEquals, context))
        {
            return false;
        }

        if (condition.In.Count > 0 && !condition.In.Select(item => Interpolate(item, context)).Contains(value))
        {
            return false;
        }

        if (condition.NotIn.Select(item => Interpolate(item, context)).Contains(value))
        {
            return false;
        }

        if (condition.LessThan is not null && !CompareNumeric(value, Interpolate(condition.LessThan, context), (left, right) => left < right))
        {
            return false;
        }

        if (condition.LessThanOrEqual is not null && !CompareNumeric(value, Interpolate(condition.LessThanOrEqual, context), (left, right) => left <= right))
        {
            return false;
        }

        if (condition.GreaterThan is not null && !CompareNumeric(value, Interpolate(condition.GreaterThan, context), (left, right) => left > right))
        {
            return false;
        }

        if (condition.GreaterThanOrEqual is not null && !CompareNumeric(value, Interpolate(condition.GreaterThanOrEqual, context), (left, right) => left >= right))
        {
            return false;
        }

        return true;
    }

    public static IReadOnlyList<ListRowSpec> HydrateRows(ControlSpec control)
    {
        if (control.Items.Count == 0)
        {
            return control.Rows;
        }

        var template = control.RowTemplate ?? new ListRowSpec
        {
            Id = "{{id}}",
            Title = "{{name}}",
            Values = control.Columns.ToDictionary(column => column.Id, column => $"{{{{{column.Id}}}}}"),
            Status = "{{status}}",
        };

        return control.Items.Select((item, index) =>
        {
            var values = item.ValuesOrItem();
            var fallbackID = NonEmpty(ValueOrNull(values, "id")) ?? $"row-{index + 1}";
            var id = NonEmpty(InterpolateItem(template.Id, values)) ?? fallbackID;
            return new ListRowSpec
            {
                Id = id,
                Title = NonEmpty(template.Title is null ? null : InterpolateItem(template.Title, values)),
                Values = template.Values.ToDictionary(pair => pair.Key, pair => InterpolateItem(pair.Value, values)),
                Status = NonEmpty(template.Status is null ? null : InterpolateItem(template.Status, values)),
                Tags = template.Tags
                    .Select(tag => tag with
                    {
                        Id = InterpolateItem(tag.Id, values),
                        Title = InterpolateItem(tag.Title, values),
                    })
                    .Where(tag => tag.Title.Trim().Length > 0)
                    .ToList(),
                Tooltip = NonEmpty(template.Tooltip is null ? null : InterpolateItem(template.Tooltip, values)),
            };
        }).ToList();
    }

    public static RenderContext RowContext(RenderContext baseContext, ListRowSpec row)
    {
        var rowValues = new Dictionary<string, string>(row.Values)
        {
            ["id"] = row.Id ?? "",
            ["title"] = row.Title ?? row.Id ?? "",
        };
        if (row.Status is not null)
        {
            rowValues["status"] = row.Status;
        }

        return baseContext with { RowValues = rowValues };
    }

    public static ControlSpec ApplyDataSourcePayload(ControlSpec control, DataSourcePayload payload) =>
        control.WithDataSourcePayload(payload);

    public static string SerializeFlatToml(IReadOnlyDictionary<string, string> values)
    {
        var lines = values
            .OrderBy(pair => pair.Key, StringComparer.Ordinal)
            .Select(pair => $"{TomlKey(pair.Key)} = {TomlValue(pair.Value)}");
        return $"{string.Join('\n', lines)}\n";
    }

    public static Dictionary<string, string> ParseFlatToml(string text)
    {
        var values = new Dictionary<string, string>();
        foreach (var rawLine in Regex.Split(text, "\r?\n"))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith('#') || !line.Contains('=', StringComparison.Ordinal))
            {
                continue;
            }

            var separator = AssignmentSeparator(line);
            if (separator < 0)
            {
                continue;
            }

            var rawKey = line[..separator].Trim();
            var rawValue = line[(separator + 1)..].Trim();
            var key = rawKey.StartsWith('"') ? ParseTomlValue(rawKey) : rawKey;
            values[key] = ParseTomlValue(rawValue);
        }

        return values;
    }

    public static double EvaluateNumeric(string? expression) => new NumericParser(expression ?? "").Parse();

    private static string? ValueOrNull(IReadOnlyDictionary<string, string> values, string key) =>
        values.TryGetValue(key, out var value) ? value : null;

    private static IReadOnlyList<string> MissingRequiredPlaceholders(IEnumerable<string> values, RenderContext context) =>
        PlaceholdersIn(values).Where(placeholder => string.IsNullOrWhiteSpace(ContextValue(context, placeholder))).ToList();

    private static string? ComputedFileStateValue(RenderContext context, string placeholder)
    {
        var separator = placeholder.LastIndexOf('.');
        if (separator <= 0 || separator >= placeholder.Length - 1)
        {
            return null;
        }

        if (ValueOrNull(context.FileStateValues, placeholder) is { } serverComputed)
        {
            return serverComputed;
        }

        var fieldID = placeholder[..separator];
        var property = placeholder[(separator + 1)..];
        var rawPath = ValueOrNull(context.FieldValues, fieldID) ?? ValueOrNull(context.ConfigValues, fieldID);

        return property switch
        {
            "pathExtension" => PathExtension(rawPath),
            _ => null,
        };
    }

    private static string PathExtension(string? path)
    {
        var name = (path ?? "").Split(['/', '\\']).LastOrDefault() ?? "";
        var dot = name.LastIndexOf('.');
        return dot >= 0 ? name[(dot + 1)..].ToLowerInvariant() : "";
    }

    private static bool CompareNumeric(string left, string right, Func<double, double, bool> op)
    {
        var leftValue = EvaluateNumeric(left);
        var rightValue = EvaluateNumeric(right);
        return double.IsFinite(leftValue) && double.IsFinite(rightValue) && op(leftValue, rightValue);
    }

    private static string InterpolateItem(string? value, IReadOnlyDictionary<string, string> values) =>
        PlaceholderPattern.Replace(value ?? "", match =>
        {
            var raw = match.Groups[1].Value.Trim();
            var placeholder = raw.StartsWith("item.", StringComparison.Ordinal) ? raw[5..] : raw;
            return ValueOrNull(values, placeholder) ?? "";
        });

    private static int AssignmentSeparator(string line)
    {
        var inQuotes = false;
        var escaped = false;
        for (var index = 0; index < line.Length; index += 1)
        {
            var character = line[index];
            if (escaped)
            {
                escaped = false;
                continue;
            }

            if (character == '\\' && inQuotes)
            {
                escaped = true;
                continue;
            }

            if (character == '"')
            {
                inQuotes = !inQuotes;
                continue;
            }

            if (character == '=' && !inQuotes)
            {
                return index;
            }
        }

        return -1;
    }

    private static string TomlKey(string key) => TomlBareKeyRegex().IsMatch(key) ? key : TomlValue(key);

    private static string TomlValue(string? value) =>
        $"\"{(value ?? "").Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal).Replace("\n", "\\n", StringComparison.Ordinal)}\"";

    private static string ParseTomlValue(string value)
    {
        if (!value.StartsWith('"') || !value.EndsWith('"'))
        {
            return value;
        }

        return TomlEscapeRegex().Replace(value[1..^1], match => match.Groups[1].Value switch
        {
            "n" => "\n",
            "r" => "\r",
            "t" => "\t",
            "\"" => "\"",
            "\\" => "\\",
            var escaped => escaped,
        });
    }

    private static string? NonEmpty(string? value)
    {
        var text = value ?? "";
        return text.Length > 0 ? text : null;
    }

    [GeneratedRegex(@"\{\{([^}]+)\}\}")]
    private static partial Regex PlaceholderRegex();

    [GeneratedRegex(@"^[A-Za-z0-9_./-]+$")]
    private static partial Regex PosixSafeShellTokenRegex();

    [GeneratedRegex(@"^[A-Za-z0-9_-]+$")]
    private static partial Regex TomlBareKeyRegex();

    [GeneratedRegex(@"\\([nrt""\\])")]
    private static partial Regex TomlEscapeRegex();

    private sealed class NumericParser(string text)
    {
        private int _index;

        public double Parse()
        {
            var value = Expression();
            SkipWhitespace();
            return _index == text.Length ? value : double.NaN;
        }

        private double Expression()
        {
            var value = Term();
            while (true)
            {
                SkipWhitespace();
                if (Consume("+"))
                {
                    value += Term();
                }
                else if (Consume("-"))
                {
                    value -= Term();
                }
                else
                {
                    return value;
                }
            }
        }

        private double Term()
        {
            var value = Factor();
            while (true)
            {
                SkipWhitespace();
                if (Consume("*"))
                {
                    value *= Factor();
                }
                else if (Consume("/"))
                {
                    value /= Factor();
                }
                else
                {
                    return value;
                }
            }
        }

        private double Factor()
        {
            SkipWhitespace();
            if (Consume("+"))
            {
                return Factor();
            }

            if (Consume("-"))
            {
                return -Factor();
            }

            if (Consume("("))
            {
                var value = Expression();
                return Consume(")") ? value : double.NaN;
            }

            return Number();
        }

        private double Number()
        {
            SkipWhitespace();
            var start = _index;
            while (_index < text.Length && (char.IsAsciiDigit(text[_index]) || text[_index] == '.'))
            {
                _index += 1;
            }

            return start == _index
                ? double.NaN
                : double.Parse(text[start.._index], CultureInfo.InvariantCulture);
        }

        private bool Consume(string token)
        {
            if (_index < text.Length && text[_index].ToString() == token)
            {
                _index += 1;
                return true;
            }

            return false;
        }

        private void SkipWhitespace()
        {
            while (_index < text.Length && char.IsWhiteSpace(text[_index]))
            {
                _index += 1;
            }
        }
    }
}
