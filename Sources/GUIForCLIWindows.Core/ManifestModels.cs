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

    [JsonPropertyName("controls")]
    public List<ControlSpec> Controls { get; init; } = [];

    [JsonPropertyName("actions")]
    public List<ActionSpec> Actions { get; init; } = [];
}

