using System.Text.Json;
using System.Text.Json.Serialization;

namespace GUIForCLIWindows.Core;

public sealed record BundleManifest
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("displayName")]
    public string DisplayName { get; init; } = "";

    [JsonPropertyName("summary")]
    public string Summary { get; init; } = "";

    [JsonPropertyName("iconName")]
    public string? IconName { get; init; }

    [JsonPropertyName("iconPath")]
    public string? IconPath { get; init; }

    [JsonPropertyName("textIcon")]
    public string? TextIcon { get; init; }

    [JsonPropertyName("terminalTextDirection")]
    public string TerminalTextDirection { get; init; } = "ltr";

    [JsonPropertyName("defaultLocalizationCode")]
    public string DefaultLocalizationCode { get; init; } = "en";

    [JsonPropertyName("pages")]
    public List<BundlePage> Pages { get; init; } = [];

    [JsonPropertyName("setup")]
    public SetupSpec Setup { get; init; } = new();

    [JsonPropertyName("exitCodeReference")]
    public List<ExitCodeReferenceSpec> ExitCodeReference { get; init; } = [];

    [JsonIgnore]
    public List<string> PageFiles { get; init; } = [];
}

public sealed record BundlePage
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("summary")]
    public string Summary { get; init; } = "";

    [JsonPropertyName("iconName")]
    public string? IconName { get; init; }

    [JsonPropertyName("textIcon")]
    public string? TextIcon { get; init; }

    [JsonPropertyName("sidebarGroup")]
    public string? SidebarGroup { get; init; }

    [JsonPropertyName("sections")]
    public List<PageSection> Sections { get; init; } = [];
}

public sealed record PageSection
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("title")]
    public string? Title { get; init; }

    [JsonPropertyName("subtitle")]
    public string? Subtitle { get; init; }

    [JsonPropertyName("iconName")]
    public string? IconName { get; init; }

    [JsonPropertyName("textIcon")]
    public string? TextIcon { get; init; }

    [JsonPropertyName("summary")]
    public string? Summary { get; init; }

    [JsonPropertyName("dataSource")]
    public DataSourceSpec? DataSource { get; init; }

    [JsonPropertyName("controls")]
    public List<ControlSpec> Controls { get; init; } = [];

    [JsonPropertyName("actions")]
    public List<ActionSpec> Actions { get; init; } = [];
}

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

    [JsonPropertyName("group")]
    public string? Group { get; init; }
}

public sealed record ListColumnSpec
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";
}

public sealed class ListItemSpec
{
    private Dictionary<string, JsonElement> _extraValues = [];

    [JsonPropertyName("values")]
    public Dictionary<string, string>? Values { get; init; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement> ExtraValues
    {
        get => _extraValues;
        set => _extraValues = value ?? [];
    }

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

public sealed record ConfigSettingSpec
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("kind")]
    public string Kind { get; init; } = "";

    [JsonPropertyName("key")]
    public string Key { get; init; } = "";

    [JsonPropertyName("value")]
    public string? Value { get; init; }

    [JsonPropertyName("label")]
    public string Label { get; init; } = "";

    [JsonPropertyName("placeholder")]
    public string? Placeholder { get; init; }

    [JsonPropertyName("tooltip")]
    public string? Tooltip { get; init; }

    [JsonPropertyName("options")]
    public List<ControlOption> Options { get; init; } = [];

    [JsonPropertyName("dataSource")]
    public DataSourceSpec? DataSource { get; init; }
}

public sealed record ConfigFileSpec
{
    [JsonPropertyName("path")]
    public string Path { get; init; } = "";
}

public sealed record ActionSpec
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("tooltip")]
    public string? Tooltip { get; init; }

    [JsonPropertyName("visibleWhen")]
    public List<ActionConditionSpec> VisibleWhen { get; init; } = [];

    [JsonPropertyName("disabledWhen")]
    public List<ActionConditionSpec> DisabledWhen { get; init; } = [];

    [JsonPropertyName("disabledTooltip")]
    public string? DisabledTooltip { get; init; }

    [JsonPropertyName("destructive")]
    public bool Destructive { get; init; }

    [JsonPropertyName("role")]
    public string? Role { get; init; }

    [JsonPropertyName("precheck")]
    public ActionPrecheckSpec? Precheck { get; init; }

    [JsonPropertyName("command")]
    public CommandSpec Command { get; init; } = new();

    [JsonPropertyName("confirm")]
    public ConfirmationSpec? Confirm { get; init; }
}

public sealed record ConfirmationSpec
{
    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("message")]
    public string Message { get; init; } = "";

    [JsonPropertyName("confirmButtonTitle")]
    public string ConfirmButtonTitle { get; init; } = "";

    [JsonPropertyName("cancelButtonTitle")]
    public string CancelButtonTitle { get; init; } = "";

    [JsonPropertyName("requiredText")]
    public string? RequiredText { get; init; }

    [JsonPropertyName("prompt")]
    public string? Prompt { get; init; }
}

public sealed record ActionConditionSpec
{
    [JsonPropertyName("placeholder")]
    public string Placeholder { get; init; } = "";

    [JsonPropertyName("exists")]
    public bool? Exists { get; init; }

    [JsonPropertyName("equals")]
    public string? EqualTo { get; init; }

    [JsonPropertyName("notEquals")]
    public string? NotEquals { get; init; }

    [JsonPropertyName("in")]
    public List<string> In { get; init; } = [];

    [JsonPropertyName("notIn")]
    public List<string> NotIn { get; init; } = [];

    [JsonPropertyName("lessThan")]
    public string? LessThan { get; init; }

    [JsonPropertyName("lessThanOrEqual")]
    public string? LessThanOrEqual { get; init; }

    [JsonPropertyName("greaterThan")]
    public string? GreaterThan { get; init; }

    [JsonPropertyName("greaterThanOrEqual")]
    public string? GreaterThanOrEqual { get; init; }
}

public sealed record CommandSpec
{
    [JsonPropertyName("executable")]
    public string Executable { get; init; } = "";

    [JsonPropertyName("arguments")]
    public List<string> Arguments { get; init; } = [];

    [JsonPropertyName("optionalArguments")]
    public List<List<string>> OptionalArguments { get; init; } = [];
}

public sealed record DataSourceSpec
{
    [JsonPropertyName("path")]
    public string Path { get; init; } = "";

    [JsonPropertyName("arguments")]
    public List<string> Arguments { get; init; } = [];

    [JsonPropertyName("workingDirectory")]
    public string? WorkingDirectory { get; init; }

    [JsonPropertyName("environment")]
    public Dictionary<string, string> Environment { get; init; } = [];
}

public sealed record ActionPrecheckSpec
{
    [JsonPropertyName("diskSpaceGB")]
    public string? DiskSpaceGB { get; init; }

    [JsonPropertyName("diskSpacePath")]
    public string? DiskSpacePath { get; init; }

    [JsonPropertyName("warningMessage")]
    public string? WarningMessage { get; init; }
}
