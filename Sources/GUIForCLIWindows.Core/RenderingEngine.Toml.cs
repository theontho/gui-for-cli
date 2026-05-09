using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace GUIForCLIWindows.Core;

public static partial class RenderingEngine
{
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

    [GeneratedRegex(@"^[A-Za-z0-9_-]+$")]
    private static partial Regex TomlBareKeyRegex();

    [GeneratedRegex(@"\\([nrt""\\])")]
    private static partial Regex TomlEscapeRegex();

}
