using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace GUIForCLIWindows.Core;

public static partial class RenderingEngine
{
    private static readonly Regex PlaceholderPattern = PlaceholderRegex();

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

    [GeneratedRegex(@"\{\{([^}]+)\}\}")]
    private static partial Regex PlaceholderRegex();

    [GeneratedRegex(@"^[A-Za-z0-9_./-]+$")]
    private static partial Regex PosixSafeShellTokenRegex();

}
