namespace GUIForCLIWindows.Core;

public sealed record RenderContext
{
    public string? BundleRootPath { get; init; }
    public string? BundleWorkspacePath { get; init; }
    public string? HomePath { get; init; }
    public IReadOnlyDictionary<string, string> FieldValues { get; init; } = new Dictionary<string, string>();
    public IReadOnlyDictionary<string, string> CheckedOptions { get; init; } = new Dictionary<string, string>();
    public IReadOnlyDictionary<string, string> ConfigValues { get; init; } = new Dictionary<string, string>();
    public IReadOnlyDictionary<string, string> RowValues { get; init; } = new Dictionary<string, string>();
    public IReadOnlyDictionary<string, string> FileStateValues { get; init; } = new Dictionary<string, string>();
}
