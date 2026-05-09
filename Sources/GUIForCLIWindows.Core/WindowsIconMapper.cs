namespace GUIForCLIWindows.Core;

public static class WindowsIconMapper
{
    private static readonly IReadOnlyDictionary<string, string> Glyphs = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["app"] = "\uECAA",
        ["archivebox"] = "\uE8B7",
        ["books.vertical"] = "\uE8F1",
        ["checkmark"] = "\uE73E",
        ["chevron.right"] = "\uE76C",
        ["doc"] = "\uE8A5",
        ["doc.text"] = "\uE8A5",
        ["folder"] = "\uE8B7",
        ["gear"] = "\uE713",
        ["globe"] = "\uE774",
        ["hammer"] = "\uE90F",
        ["info"] = "\uE946",
        ["list.bullet"] = "\uEA37",
        ["play"] = "\uE768",
        ["plus"] = "\uE710",
        ["questionmark.circle"] = "\uE897",
        ["server.rack"] = "\uE968",
        ["terminal"] = "\uE756",
        ["trash"] = "\uE74D",
        ["wrench"] = "\uE90F",
        ["xmark"] = "\uE711",
    };

    public static string GlyphFor(string? semanticIconName) =>
        !string.IsNullOrWhiteSpace(semanticIconName) && Glyphs.TryGetValue(semanticIconName, out var glyph)
            ? glyph
            : "\uECAA";
}

public static class WindowsSetupKinds
{
    public const string PowershellScript = "powershellScript";
    public const string WingetPackage = "wingetPackage";
    public const string Pixi = "pixi";

    public static bool IsWindowsNative(string kind) =>
        string.Equals(kind, PowershellScript, StringComparison.Ordinal)
        || string.Equals(kind, WingetPackage, StringComparison.Ordinal)
        || string.Equals(kind, Pixi, StringComparison.Ordinal);

    public static RenderedCommand? CommandFor(SetupStepSpec step)
    {
        if (step.Command is not null)
        {
            return new RenderedCommand(step.Command.Executable, step.Command.Arguments);
        }

        return step.Kind switch
        {
            "pathTool" when !string.IsNullOrWhiteSpace(step.Value) => new RenderedCommand("where.exe", [step.Value]),
            "setupScript" when !string.IsNullOrWhiteSpace(step.Value) => new RenderedCommand(Path.ChangeExtension(step.Value, ".ps1"), step.Arguments),
            "pixiRun" when !string.IsNullOrWhiteSpace(step.Value) => new RenderedCommand("pixi.exe", ["run", step.Value]),
            PowershellScript when !string.IsNullOrWhiteSpace(step.Script ?? step.Value) => new RenderedCommand(step.Script ?? step.Value!, step.Arguments),
            WingetPackage when !string.IsNullOrWhiteSpace(step.PackageId) => new RenderedCommand("winget.exe", ["list", "--id", step.PackageId, "--exact"]),
            Pixi => new RenderedCommand("pixi.exe", ["--version"]),
            _ => null,
        };
    }
}
