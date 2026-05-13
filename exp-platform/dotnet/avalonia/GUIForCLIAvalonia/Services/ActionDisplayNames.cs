using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Services;

public static class ActionDisplayNames
{
    public static IReadOnlyList<string> ForPlaceholders(BundleManifest manifest, IReadOnlyList<string> placeholders)
    {
        var names = PlaceholderDisplayNames(manifest);
        return placeholders.Select(placeholder => DisplayNameForPlaceholder(placeholder, names)).Distinct(StringComparer.Ordinal).ToList();
    }

    private static Dictionary<string, string> PlaceholderDisplayNames(BundleManifest manifest)
    {
        var names = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var control in RenderingEngine.AllControls(manifest))
        {
            Add(names, control.Id, control.Label);
            foreach (var setting in control.Settings)
            {
                var label = string.IsNullOrWhiteSpace(setting.Label) ? setting.Id : setting.Label;
                Add(names, setting.Id, label);
                Add(names, RenderingEngine.ConfigValueKey(control, setting), label);
                if (!string.IsNullOrWhiteSpace(setting.Key))
                {
                    Add(names, $"config.{setting.Key}", label);
                }
            }
        }

        return names;
    }

    private static string DisplayNameForPlaceholder(string placeholder, IReadOnlyDictionary<string, string> displayNames)
    {
        if (displayNames.TryGetValue(placeholder, out var exact))
        {
            return exact;
        }

        var dotIndex = placeholder.IndexOf('.', StringComparison.Ordinal);
        if (dotIndex > 0 && displayNames.TryGetValue(placeholder[..dotIndex], out var baseName))
        {
            return $"{baseName} {DisplayNameForPlaceholderSuffix(placeholder[(dotIndex + 1)..])}";
        }

        return placeholder;
    }

    private static string DisplayNameForPlaceholderSuffix(string suffix) => suffix switch
    {
        "fileSizeGB" => "file size",
        "isIndexed" => "index status",
        "isSorted" => "sort status",
        "pathExtension" => "file type",
        _ => suffix.Replace('.', ' '),
    };

    private static void Add(Dictionary<string, string> names, string key, string label)
    {
        if (!string.IsNullOrWhiteSpace(key) && !string.IsNullOrWhiteSpace(label))
        {
            names[key] = label;
        }
    }
}
