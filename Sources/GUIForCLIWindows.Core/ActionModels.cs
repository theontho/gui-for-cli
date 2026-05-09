using System.Text.Json;
using System.Text.Json.Serialization;

namespace GUIForCLIWindows.Core;

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

