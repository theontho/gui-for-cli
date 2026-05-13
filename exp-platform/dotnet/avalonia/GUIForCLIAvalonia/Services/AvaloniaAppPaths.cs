namespace GUIForCLIAvalonia.Services;

public sealed class AvaloniaAppPaths
{
    private AvaloniaAppPaths(string root)
    {
        Root = root;
    }

    public string Root { get; }

    public static AvaloniaAppPaths ForCurrentUser()
    {
        var overridePath = Environment.GetEnvironmentVariable("GUI_FOR_CLI_CONFIG_DIR");
        if (!string.IsNullOrWhiteSpace(overridePath))
        {
            return new AvaloniaAppPaths(Path.GetFullPath(overridePath));
        }

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var root = OperatingSystem.IsMacOS()
            ? Path.Combine(home, "Library", "Application Support", "gui-for-cli", "avalonia")
            : OperatingSystem.IsWindows()
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "gui-for-cli", "avalonia")
                : Path.Combine(Environment.GetEnvironmentVariable("XDG_CONFIG_HOME") ?? Path.Combine(home, ".config"), "gui-for-cli", "avalonia");
        return new AvaloniaAppPaths(root);
    }

    public string BundleWorkspace(string bundleID) =>
        Path.Combine(Root, "bundles", SafePathSegment(bundleID));

    public void EnsureBundleDirectories(string bundleID) =>
        Directory.CreateDirectory(BundleWorkspace(bundleID));

    private static string SafePathSegment(string value)
    {
        var chars = value.Select(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.' ? character : '-').ToArray();
        var segment = new string(chars).Trim('-', '.');
        return string.IsNullOrWhiteSpace(segment) ? "bundle" : segment;
    }
}
