using System.Globalization;

namespace GUIForCLIWindows.Core;

public sealed class BundleIconMap
{
    public const string SfSymbolsSource = "sf-symbols";
    public const string WindowsSource = "windows";
    public const string BootstrapSource = "bootstrap";
    public const string EmojiSource = "emoji";

    public static BundleIconMap Empty { get; } = new(
        new Dictionary<string, IReadOnlyDictionary<string, string>>(StringComparer.Ordinal));

    public BundleIconMap(IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> sources)
    {
        Sources = sources;
    }

    public IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> Sources { get; }

    public string? Resolve(string source, string? key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            return null;
        }

        return Sources.TryGetValue(source, out var values)
            && values.TryGetValue(key.Trim(), out var value)
            ? value
            : null;
    }

    public BundleIconMap Merge(BundleIconMap overrides)
    {
        var merged = Sources.ToDictionary(
            pair => pair.Key,
            pair => new Dictionary<string, string>(pair.Value, StringComparer.Ordinal),
            StringComparer.Ordinal);
        foreach (var (source, values) in overrides.Sources)
        {
            if (!merged.TryGetValue(source, out var target))
            {
                target = new Dictionary<string, string>(StringComparer.Ordinal);
                merged[source] = target;
            }

            foreach (var (key, value) in values)
            {
                target[key] = value;
            }
        }

        return new BundleIconMap(merged.ToDictionary(
            pair => pair.Key,
            pair => (IReadOnlyDictionary<string, string>)pair.Value,
            StringComparer.Ordinal));
    }

    public static BundleIconMap Parse(string text)
    {
        var sources = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
        string? currentSource = null;
        var lines = text.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
        for (var index = 0; index < lines.Length; index++)
        {
            var rawLine = lines[index];
            var lineNumber = index + 1;
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith('#'))
            {
                continue;
            }

            if (line.StartsWith('[') && line.EndsWith(']'))
            {
                currentSource = line[1..^1].Trim();
                if (currentSource.Length == 0)
                {
                    throw InvalidLine(lineNumber, rawLine);
                }

                sources.TryAdd(currentSource, new Dictionary<string, string>(StringComparer.Ordinal));
                continue;
            }

            if (currentSource is null)
            {
                throw InvalidLine(lineNumber, rawLine);
            }

            var equals = FindUnescapedEquals(line);
            if (equals < 0)
            {
                throw InvalidLine(lineNumber, rawLine);
            }

            var key = UnquoteKey(line[..equals].Trim());
            var rawValue = line[(equals + 1)..].TrimStart();
            sources[currentSource][key] = ParseStringValue(rawValue, lineNumber, rawLine);
        }

        return new BundleIconMap(sources.ToDictionary(
            pair => pair.Key,
            pair => (IReadOnlyDictionary<string, string>)pair.Value,
            StringComparer.Ordinal));
    }

    private static int FindUnescapedEquals(string line)
    {
        var escaped = false;
        var inString = false;
        for (var index = 0; index < line.Length; index++)
        {
            var character = line[index];
            if (escaped)
            {
                escaped = false;
                continue;
            }

            if (character == '\\')
            {
                escaped = true;
                continue;
            }

            if (character == '"')
            {
                inString = !inString;
                continue;
            }

            if (!inString && character == '=')
            {
                return index;
            }
        }

        return -1;
    }

    private static string UnquoteKey(string key) =>
        key.StartsWith('"') && key.EndsWith('"') ? key[1..^1] : key;

    private static string ParseStringValue(string rawValue, int lineNumber, string rawLine)
    {
        if (!rawValue.StartsWith('"'))
        {
            throw InvalidLine(lineNumber, rawLine);
        }

        var escaped = false;
        for (var index = 1; index < rawValue.Length; index++)
        {
            var character = rawValue[index];
            if (escaped)
            {
                escaped = false;
                continue;
            }

            if (character == '\\')
            {
                escaped = true;
                continue;
            }

            if (character == '"')
            {
                var trailing = rawValue[(index + 1)..].Trim();
                if (trailing.Length > 0 && !trailing.StartsWith('#'))
                {
                    throw InvalidLine(lineNumber, rawLine);
                }

                return Unescape(rawValue[1..index], lineNumber, rawLine);
            }
        }

        throw InvalidLine(lineNumber, rawLine);
    }

    private static string Unescape(string value, int lineNumber, string rawLine)
    {
        var result = new List<char>();
        for (var index = 0; index < value.Length; index++)
        {
            var character = value[index];
            if (character != '\\')
            {
                result.Add(character);
                continue;
            }

            index += 1;
            if (index >= value.Length)
            {
                throw InvalidLine(lineNumber, rawLine);
            }

            var escaped = value[index];
            switch (escaped)
            {
                case 'n':
                    result.Add('\n');
                    break;
                case 'r':
                    result.Add('\r');
                    break;
                case 't':
                    result.Add('\t');
                    break;
                case '"':
                    result.Add('"');
                    break;
                case '\\':
                    result.Add('\\');
                    break;
                case 'u':
                case 'U':
                    var length = escaped == 'u' ? 4 : 8;
                    if (index + length >= value.Length)
                    {
                        throw InvalidLine(lineNumber, rawLine);
                    }

                    var hex = value.Substring(index + 1, length);
                    if (!int.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var codePoint))
                    {
                        throw InvalidLine(lineNumber, rawLine);
                    }

                    result.AddRange(char.ConvertFromUtf32(codePoint));
                    index += length;
                    break;
                default:
                    throw InvalidLine(lineNumber, rawLine);
            }
        }

        return new string([.. result]);
    }

    private static InvalidOperationException InvalidLine(int lineNumber, string rawLine) =>
        new($"Invalid icon map TOML at line {lineNumber}: {rawLine}");
}
