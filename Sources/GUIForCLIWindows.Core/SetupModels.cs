using System.Text.Json;
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

