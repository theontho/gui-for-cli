using System.Text.Json.Serialization;

namespace GUIForCLIWindows.Core;

public sealed record SetupSpec
{
    [JsonPropertyName("steps")]
    public List<SetupStepSpec> Steps { get; init; } = [];
}

public sealed record SetupStepSpec
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("label")]
    public string Label { get; init; } = "";

    [JsonPropertyName("kind")]
    public string Kind { get; init; } = "";

    [JsonPropertyName("command")]
    public CommandSpec? Command { get; init; }

    [JsonPropertyName("value")]
    public string? Value { get; init; }

    [JsonPropertyName("arguments")]
    public List<string> Arguments { get; init; } = [];

    [JsonPropertyName("environment")]
    public Dictionary<string, string> Environment { get; init; } = [];

    [JsonPropertyName("workingDirectory")]
    public string? WorkingDirectory { get; init; }

    [JsonPropertyName("optional")]
    public bool Optional { get; init; }

    [JsonPropertyName("packageId")]
    public string? PackageId { get; init; }

    [JsonPropertyName("script")]
    public string? Script { get; init; }

    [JsonPropertyName("platforms")]
    public List<string> Platforms { get; init; } = [];
}

public sealed record ExitCodeReferenceSpec
{
    [JsonPropertyName("code")]
    public int Code { get; init; }

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("summary")]
    public string Summary { get; init; } = "";

    [JsonPropertyName("severity")]
    public string Severity { get; init; } = "error";
}

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

    [JsonPropertyName("values")]
    public Dictionary<string, string>? Values { get; init; }
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

    [JsonPropertyName("selectedPageID")]
    public string? SelectedPageID { get; init; }

    [JsonPropertyName("setupRun")]
    public BundleSetupRunState? SetupRun { get; init; }

    [JsonPropertyName("iconSet")]
    public string IconSet { get; init; } = "platform";

    [JsonPropertyName("colorTheme")]
    public string ColorTheme { get; init; } = "system";

    [JsonPropertyName("webUIFont")]
    public string WebUIFont { get; init; } = "system";
}

public sealed record BundleSetupRunState
{
    [JsonPropertyName("status")]
    public string Status { get; init; } = "notStarted";

    [JsonPropertyName("results")]
    public List<BundleSetupStepRunState> Results { get; init; } = [];

    [JsonPropertyName("completedAt")]
    public string? CompletedAt { get; init; }

    [JsonPropertyName("error")]
    public string? Error { get; init; }
}

public sealed record BundleSetupStepRunState
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = "";

    [JsonPropertyName("label")]
    public string Label { get; init; } = "";

    [JsonPropertyName("kind")]
    public string Kind { get; init; } = "";

    [JsonPropertyName("command")]
    public string? Command { get; init; }

    [JsonPropertyName("status")]
    public string Status { get; init; } = "";

    [JsonPropertyName("exitCode")]
    public int? ExitCode { get; init; }
}
