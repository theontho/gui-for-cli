using System.Text.Json;
using System.Text.Json.Serialization;

namespace GUIForCLIWindows.Core;

public sealed record ControlSpec
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("label")]
    public string Label { get; init; } = "";

    [JsonPropertyName("kind")]
    public string Kind { get; init; } = "";

    [JsonPropertyName("value")]
    public string? Value { get; init; }

    [JsonPropertyName("placeholder")]
    public string? Placeholder { get; init; }

    [JsonPropertyName("tooltip")]
    public string? Tooltip { get; init; }

    [JsonPropertyName("options")]
    public List<ControlOption> Options { get; init; } = [];

    [JsonPropertyName("columns")]
    public List<ListColumnSpec> Columns { get; init; } = [];

    [JsonPropertyName("rows")]
    public List<ListRowSpec> Rows { get; init; } = [];

    [JsonPropertyName("rowTemplate")]
    public ListRowSpec? RowTemplate { get; init; }

    [JsonPropertyName("items")]
    public List<ListItemSpec> Items { get; init; } = [];

    [JsonPropertyName("rowActions")]
    public List<ActionSpec> RowActions { get; init; } = [];

    [JsonPropertyName("settings")]
    public List<ConfigSettingSpec> Settings { get; init; } = [];

    [JsonPropertyName("configFile")]
    public ConfigFileSpec? ConfigFile { get; init; }

    [JsonPropertyName("dataSource")]
    public DataSourceSpec? DataSource { get; init; }

    public ControlSpec WithDataSourcePayload(DataSourcePayload payload) => this with
    {
        Options = payload.Options ?? Options,
        Rows = payload.Rows ?? Rows,
        Items = payload.Rows is not null ? [] : payload.Items ?? Items,
        RowActions = payload.RowActions ?? payload.Actions ?? RowActions,
    };
}

public sealed record ControlOption
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("selected")]
    public bool Selected { get; init; }
}

public sealed record ListColumnSpec
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";
}

public sealed record ListItemSpec
{
    [JsonPropertyName("values")]
    public Dictionary<string, string>? Values { get; init; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement> ExtraValues { get; init; } = [];

    public Dictionary<string, string> ValuesOrItem()
    {
        if (Values is { Count: > 0 })
        {
            return new Dictionary<string, string>(Values);
        }

        return ExtraValues.ToDictionary(pair => pair.Key, pair => pair.Value.ValueKind switch
        {
            JsonValueKind.String => pair.Value.GetString() ?? "",
            JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False => pair.Value.ToString(),
            _ => "",
        });
    }
}

public sealed record ListRowSpec
{
    [JsonPropertyName("id")]
    public string? Id { get; init; }

    [JsonPropertyName("title")]
    public string? Title { get; init; }

    [JsonPropertyName("values")]
    public Dictionary<string, string> Values { get; init; } = [];

    [JsonPropertyName("status")]
    public string? Status { get; init; }

    [JsonPropertyName("tags")]
    public List<TagSpec> Tags { get; init; } = [];

    [JsonPropertyName("tooltip")]
    public string? Tooltip { get; init; }
}

public sealed record TagSpec
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("style")]
    public string? Style { get; init; }
}

