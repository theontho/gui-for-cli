using System.Text.RegularExpressions;

namespace GUIForCLIWindows.Core;

public static partial class LocalizationEngine
{
    public static Dictionary<string, string> ParseTomlStrings(string text)
    {
        var values = new Dictionary<string, string>();
        var lines = Regex.Split(text, "\r?\n");
        var index = 0;
        while (index < lines.Length)
        {
            var rawLine = lines[index];
            var lineNumber = index + 1;
            var line = rawLine.Trim();
            index += 1;

            if (line.Length == 0 || line.StartsWith('#'))
            {
                continue;
            }

            if (line.StartsWith('[') && line.EndsWith(']'))
            {
                throw new FormatException($"Invalid localization TOML at line {lineNumber}: {rawLine}");
            }

            var equals = FindUnescapedEquals(line);
            if (equals < 0)
            {
                throw new FormatException($"Invalid localization TOML at line {lineNumber}: {rawLine}");
            }

            var key = UnquoteKey(line[..equals].Trim());
            var rawValue = line[(equals + 1)..].TrimStart();
            if (rawValue.StartsWith("\"\"\"", StringComparison.Ordinal))
            {
                rawValue = rawValue[3..];
                var collected = new List<string>();
                var sameLineEnd = rawValue.IndexOf("\"\"\"", StringComparison.Ordinal);
                if (sameLineEnd >= 0)
                {
                    collected.Add(rawValue[..sameLineEnd]);
                }
                else
                {
                    collected.Add(rawValue);
                    var foundEnd = false;
                    while (index < lines.Length)
                    {
                        var nextLine = lines[index];
                        index += 1;
                        var end = nextLine.IndexOf("\"\"\"", StringComparison.Ordinal);
                        if (end >= 0)
                        {
                            collected.Add(nextLine[..end]);
                            foundEnd = true;
                            break;
                        }

                        collected.Add(nextLine);
                    }

                    if (!foundEnd)
                    {
                        throw new FormatException($"Unterminated multiline localization string: {key}");
                    }
                }

                if (collected.Count > 0 && collected[0] == "")
                {
                    collected.RemoveAt(0);
                }

                if (collected.Count > 0 && collected[^1] == "")
                {
                    collected.RemoveAt(collected.Count - 1);
                }

                values[key] = string.Join('\n', collected);
                continue;
            }

            if (!rawValue.StartsWith('"'))
            {
                throw new FormatException($"Invalid localization TOML at line {lineNumber}: {rawLine}");
            }

            var closing = FindClosingQuote(rawValue);
            if (closing < 0)
            {
                throw new FormatException($"Invalid localization TOML at line {lineNumber}: {rawLine}");
            }

            var trailing = rawValue[(closing + 1)..].Trim();
            if (trailing.Length > 0 && !trailing.StartsWith('#'))
            {
                throw new FormatException($"Invalid localization TOML at line {lineNumber}: {rawLine}");
            }

            values[key] = UnescapeTomlString(rawValue[1..closing]);
        }

        return values;
    }

    public static Dictionary<string, string> MergeTables(params IReadOnlyDictionary<string, string>?[] tables)
    {
        var merged = new Dictionary<string, string>();
        foreach (var table in tables.Where(table => table is not null))
        {
            foreach (var (key, value) in table!)
            {
                merged[key] = value;
            }
        }

        return merged;
    }

    private static int FindUnescapedEquals(string line)
    {
        var quoted = false;
        var escaped = false;
        for (var index = 0; index < line.Length; index += 1)
        {
            var character = line[index];
            if (escaped)
            {
                escaped = false;
            }
            else if (character == '\\')
            {
                escaped = true;
            }
            else if (character == '"')
            {
                quoted = !quoted;
            }
            else if (character == '=' && !quoted)
            {
                return index;
            }
        }

        return -1;
    }

    private static int FindClosingQuote(string value)
    {
        var escaped = false;
        for (var index = 1; index < value.Length; index += 1)
        {
            var character = value[index];
            if (escaped)
            {
                escaped = false;
            }
            else if (character == '\\')
            {
                escaped = true;
            }
            else if (character == '"')
            {
                return index;
            }
        }

        return -1;
    }

    private static string UnquoteKey(string key) =>
        key.StartsWith('"') && key.EndsWith('"') ? UnescapeTomlString(key[1..^1]) : key;

    private static string UnescapeTomlString(string value) =>
        TomlEscapeRegex().Replace(value, match => match.Groups[1].Value switch
        {
            "n" => "\n",
            "r" => "\r",
            "t" => "\t",
            "\"" => "\"",
            "\\" => "\\",
            var escaped => escaped,
        });

    [GeneratedRegex(@"\\([nrt""\\])")]
    private static partial Regex TomlEscapeRegex();
}
