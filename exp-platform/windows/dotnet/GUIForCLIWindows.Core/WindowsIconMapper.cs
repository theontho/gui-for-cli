namespace GUIForCLIWindows.Core;

public static class WindowsIconMapper
{
    private const string DefaultGlyph = "\uECAA";

    public static string GlyphFor(string? semanticIconName, BundleIconMap iconMap)
    {
        var mapped = iconMap?.Resolve(BundleIconMap.WindowsSource, semanticIconName);
        return string.IsNullOrWhiteSpace(mapped) ? DefaultGlyph : mapped;
    }
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
            "pixiRun" when !string.IsNullOrWhiteSpace(step.Value) => new RenderedCommand("pixi.exe", ["run", step.Value, .. step.Arguments]),
            PowershellScript when !string.IsNullOrWhiteSpace(step.Script ?? step.Value) => new RenderedCommand(step.Script ?? step.Value!, step.Arguments),
            WingetPackage when !string.IsNullOrWhiteSpace(step.PackageId) => new RenderedCommand("winget.exe", ["list", "--id", step.PackageId, "--exact"]),
            Pixi => new RenderedCommand("pixi.exe", ["--version"]),
            _ => null,
        };
    }
}
