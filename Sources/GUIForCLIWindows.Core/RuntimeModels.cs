using System.Text.Json;
using System.Text.Json.Serialization;

namespace GUIForCLIWindows.Core;

public sealed record RenderedCommand(string Executable, IReadOnlyList<string> Arguments);

public sealed record DataSourcePayload
{
    [JsonPropertyName("options")]
    public List<ControlOption>? Options { get; init; }

    [JsonPropertyName("rows")]
    public List<ListRowSpec>? Rows { get; init; }

    [JsonPropertyName("items")]
    public List<ListItemSpec>? Items { get; init; }

    [JsonPropertyName("rowActions")]
    public List<ActionSpec>? RowActions { get; init; }

    [JsonPropertyName("actions")]
    public List<ActionSpec>? Actions { get; init; }
}

public sealed record BundleState
{
    [JsonPropertyName("localizationCode")]
    public string? LocalizationCode { get; init; }

    [JsonPropertyName("configFilePaths")]
    public Dictionary<string, string> ConfigFilePaths { get; init; } = [];

    [JsonPropertyName("fieldValues")]
    public Dictionary<string, string> FieldValues { get; init; } = [];

    [JsonPropertyName("checkedOptions")]
    public Dictionary<string, List<string>> CheckedOptions { get; init; } = [];

    [JsonPropertyName("iconSet")]
    public string IconSet { get; init; } = "platform";

    [JsonPropertyName("colorTheme")]
    public string ColorTheme { get; init; } = "system";
}
