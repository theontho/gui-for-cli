namespace GUIForCLIWindows.Core;

public sealed record WindowsAppPaths(string LocalRoot, string RoamingRoot)
{
    public static WindowsAppPaths ForCurrentUser(string applicationName = "gui-for-cli")
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var roamingAppData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrWhiteSpace(localAppData))
        {
            throw new InvalidOperationException("LOCALAPPDATA is not available for the current user.");
        }

        if (string.IsNullOrWhiteSpace(roamingAppData))
        {
            throw new InvalidOperationException("APPDATA is not available for the current user.");
        }

        return new WindowsAppPaths(
            Path.Combine(localAppData, applicationName),
            Path.Combine(roamingAppData, applicationName));
    }

    public string BundleWorkspace(string bundleID) =>
        Path.Combine(LocalRoot, "Bundles", SafePathSegment(bundleID));

    public string BundleStateFile(string bundleID) =>
        Path.Combine(BundleWorkspace(bundleID), "state.json");

    public string BundleConfigDirectory(string bundleID) =>
        Path.Combine(BundleWorkspace(bundleID), "Config");

    public string BundleConfigFile(string bundleID, string fileName) =>
        Path.Combine(BundleConfigDirectory(bundleID), SafePathSegment(fileName));

    public string SettingsFile() =>
        Path.Combine(RoamingRoot, "settings.json");

    public void EnsureBundleDirectories(string bundleID)
    {
        Directory.CreateDirectory(BundleWorkspace(bundleID));
        Directory.CreateDirectory(BundleConfigDirectory(bundleID));
    }

    public static string SafePathSegment(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
        {
            throw new ArgumentException("Path segment must not be empty.", nameof(value));
        }

        var characters = trimmed.Select(character => WindowsInvalidFileNameCharacters.Contains(character) || char.IsControl(character) ? '_' : character).ToArray();
        var segment = new string(characters).Trim('.');
        return segment.Length == 0
            ? throw new ArgumentException("Path segment must contain at least one valid character.", nameof(value))
            : segment;
    }

    private const string WindowsInvalidFileNameCharacters = "<>:\"/\\|?*";
}
