namespace GUIForCLIWindows.Core;

public static class WindowsIconMapper
{
    private static readonly IReadOnlyDictionary<string, string> Glyphs = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["app"] = "\uECAA",
        ["archivebox"] = "\uE8B7",
        ["arrow.clockwise.circle"] = "\uE72C",
        ["arrow.down.circle"] = "\uE896",
        ["arrow.triangle.2.circlepath"] = "\uE72C",
        ["arrow.triangle.merge"] = "\uE8B0",
        ["books.vertical"] = "\uE8F1",
        ["checkmark"] = "\uE73E",
        ["checkmark.circle.fill"] = "\uE73E",
        ["checkmark.seal"] = "\uE73E",
        ["checklist"] = "\uE9D5",
        ["chevron.right"] = "\uE76C",
        ["doc"] = "\uE8A5",
        ["doc.badge.gearshape"] = "\uE713",
        ["doc.text"] = "\uE8A5",
        ["doc.text.magnifyingglass"] = "\uE721",
        ["externaldrive"] = "\uEDA2",
        ["externaldrive.connected.to.line.below"] = "\uEDA2",
        ["folder"] = "\uE8B7",
        ["folder.badge.gearshape"] = "\uE713",
        ["gear"] = "\uE713",
        ["gearshape"] = "\uE713",
        ["globe"] = "\uE774",
        ["hammer"] = "\uE90F",
        ["info"] = "\uE946",
        ["list.bullet"] = "\uEA37",
        ["number.circle"] = "\uF146",
        ["pawprint"] = "\uE734",
        ["person.2.wave.2"] = "\uE716",
        ["person.3.sequence"] = "\uE716",
        ["play"] = "\uE768",
        ["plus"] = "\uE710",
        ["point.3.connected.trianglepath.dotted"] = "\uE774",
        ["questionmark.circle"] = "\uE897",
        ["scissors"] = "\uE8C6",
        ["server.rack"] = "\uE968",
        ["square.grid.3x3"] = "\uE80A",
        ["stethoscope"] = "\uE95E",
        ["tablecells"] = "\uE80A",
        ["text.badge.checkmark"] = "\uE73E",
        ["text.page"] = "\uE8A5",
        ["text.page.badge.magnifyingglass"] = "\uE721",
        ["terminal"] = "\uE756",
        ["tray.and.arrow.down"] = "\uE896",
        ["trash"] = "\uE74D",
        ["tree"] = "\uE8F1",
        ["waveform.path.ecg"] = "\uEC4A",
        ["waveform.path.ecg.rectangle"] = "\uEC4A",
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
            "pixiRun" when !string.IsNullOrWhiteSpace(step.Value) => new RenderedCommand("pixi.exe", ["run", step.Value, .. step.Arguments]),
            PowershellScript when !string.IsNullOrWhiteSpace(step.Script ?? step.Value) => new RenderedCommand(step.Script ?? step.Value!, step.Arguments),
            WingetPackage when !string.IsNullOrWhiteSpace(step.PackageId) => new RenderedCommand("winget.exe", ["list", "--id", step.PackageId, "--exact"]),
            Pixi => new RenderedCommand("pixi.exe", ["--version"]),
            _ => null,
        };
    }
}
