using System.Text.Json;

namespace GUIForCLIWindows.Core;

public sealed record ConfigLoadResult(string Path, IReadOnlyDictionary<string, string> Values);
public sealed record ConfigSaveResult(string Path, int KeyCount);

public static class BundleStateStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public static BundleState EmptyBundleState() => new();

    public static string NormalizeIconSet(string? value) => value == "emoji" ? "emoji" : "platform";

    public static string NormalizeColorTheme(string? value) => value is "light" or "dark" ? value : "system";

    public static string NormalizeWebUIFont(string? value) => value is "system" or "serif" or "mono" ? value : "system";

    public static async Task<BundleState> LoadBundleStateAsync(string bundleWorkspace, CancellationToken cancellationToken = default)
    {
        var path = BundleStatePath(bundleWorkspace);
        if (!File.Exists(path))
        {
            return EmptyBundleState();
        }

        await using var stream = File.OpenRead(path);
        var state = await JsonSerializer.DeserializeAsync<BundleState>(stream, JsonOptions, cancellationToken).ConfigureAwait(false)
            ?? EmptyBundleState();
        return NormalizeState(state);
    }

    public static async Task<BundleState> SaveBundleStateAsync(string bundleWorkspace, BundleState state, CancellationToken cancellationToken = default)
    {
        var next = NormalizeState(state);
        Directory.CreateDirectory(bundleWorkspace);
        var path = BundleStatePath(bundleWorkspace);
        var tempPath = Path.Combine(bundleWorkspace, $"{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            await File.WriteAllTextAsync(tempPath, $"{JsonSerializer.Serialize(next, JsonOptions)}\n", cancellationToken)
                .ConfigureAwait(false);
            if (File.Exists(path))
            {
                File.Replace(tempPath, path, null);
            }
            else
            {
                File.Move(tempPath, path);
            }
        }
        finally
        {
            if (File.Exists(tempPath))
            {
                File.Delete(tempPath);
            }
        }

        return next;
    }

    public static string BundleStatePath(string bundleWorkspace) => Path.Combine(bundleWorkspace, "state.json");

    public static Dictionary<string, string> InitialConfigFilePaths(BundleManifest manifest, BundleState state) =>
        RenderingEngine.ConfigEditorControls(manifest)
            .Where(control => control.ConfigFile is not null)
            .ToDictionary(
                control => control.Id,
                control => state.ConfigFilePaths.TryGetValue(control.Id, out var configured)
                    ? configured
                    : control.ConfigFile!.Path,
                StringComparer.Ordinal);

    public static async Task<Dictionary<string, string>> InitialConfigValuesAsync(
        BundleManifest manifest,
        IReadOnlyDictionary<string, string> configFilePaths,
        string bundleWorkspace,
        CancellationToken cancellationToken = default)
    {
        var values = RenderingEngine.InitialConfigValues(manifest);
        foreach (var control in RenderingEngine.ConfigEditorControls(manifest))
        {
            if (control.ConfigFile is null || !configFilePaths.TryGetValue(control.Id, out var requestedPath))
            {
                continue;
            }

            var filePath = ConfigPath(control, requestedPath, bundleWorkspace);
            if (!File.Exists(filePath))
            {
                continue;
            }

            var fileValues = RenderingEngine.ParseFlatToml(await File.ReadAllTextAsync(filePath, cancellationToken).ConfigureAwait(false));
            foreach (var setting in control.Settings)
            {
                if (fileValues.TryGetValue(SettingKey(setting), out var value))
                {
                    values[RenderingEngine.ConfigValueKey(control, setting)] = value;
                }
            }
        }

        return values;
    }

    public static Dictionary<string, string> InitialFieldValues(
        BundleManifest manifest,
        IReadOnlyDictionary<string, string> configValues,
        BundleState state)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var control in RenderingEngine.AllControls(manifest).Where(control => RenderingEngine.PersistsFieldValue(control.Kind)))
        {
            values[control.Id] = control.Value ?? "";
        }

        foreach (var control in RenderingEngine.AllControls(manifest).Where(control => RenderingEngine.PersistsFieldValue(control.Kind)))
        {
            if (ConfigSettingBindings(manifest, control.Id).Count == 0
                && state.FieldValues.TryGetValue(control.Id, out var savedValue))
            {
                values[control.Id] = savedValue;
            }
        }

        foreach (var control in RenderingEngine.ConfigEditorControls(manifest))
        {
            foreach (var setting in control.Settings)
            {
                var value = configValues.TryGetValue(RenderingEngine.ConfigValueKey(control, setting), out var configValue)
                    ? configValue
                    : setting.Value ?? "";
                var key = SettingKey(setting);
                if (values.ContainsKey(key))
                {
                    values[key] = value;
                }

                if (values.ContainsKey(setting.Id))
                {
                    values[setting.Id] = value;
                }
            }
        }

        return values;
    }

    public static Dictionary<string, IReadOnlyList<string>> InitialCheckedOptions(
        BundleManifest manifest,
        IReadOnlyDictionary<string, string> configValues,
        BundleState state)
    {
        var values = new Dictionary<string, IReadOnlyList<string>>();
        foreach (var control in RenderingEngine.AllControls(manifest).Where(control => control.Kind == "checkboxGroup"))
        {
            var binding = ConfigSettingBindings(manifest, control.Id).FirstOrDefault();
            if (binding is not null)
            {
                var key = RenderingEngine.ConfigValueKey(binding.Control, binding.Setting);
                var configValue = configValues.TryGetValue(key, out var value) ? value : binding.Setting.Value ?? "";
                values[control.Id] = configValue.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
            }
            else if (state.CheckedOptions.TryGetValue(control.Id, out var saved))
            {
                values[control.Id] = saved;
            }
            else
            {
                values[control.Id] = control.Options.Where(option => option.Selected).Select(option => option.Id).ToList();
            }
        }

        return values;
    }

    public static IReadOnlyList<ConfigSettingBinding> ConfigSettingBindings(BundleManifest manifest, string fieldID) =>
        RenderingEngine.ConfigEditorControls(manifest)
            .SelectMany(control => control.Settings
                .Where(setting => setting.Id == fieldID || SettingKey(setting) == fieldID)
                .Select(setting => new ConfigSettingBinding(control, setting)))
            .ToList();

    public static async Task<ConfigLoadResult> LoadConfigAsync(
        ControlSpec control,
        string requestedPath,
        string bundleWorkspace,
        CancellationToken cancellationToken = default)
    {
        var filePath = ConfigPath(control, requestedPath, bundleWorkspace);
        var fileValues = File.Exists(filePath)
            ? RenderingEngine.ParseFlatToml(await File.ReadAllTextAsync(filePath, cancellationToken).ConfigureAwait(false))
            : [];

        return new ConfigLoadResult(
            filePath,
            control.Settings.ToDictionary(
                setting => SettingKey(setting),
                setting => fileValues.TryGetValue(SettingKey(setting), out var value) ? value : setting.Value ?? "",
                StringComparer.Ordinal));
    }

    public static async Task<ConfigSaveResult> SaveConfigAsync(
        ControlSpec control,
        string requestedPath,
        IReadOnlyDictionary<string, string> values,
        string bundleWorkspace,
        CancellationToken cancellationToken = default)
    {
        var filePath = ConfigPath(control, requestedPath, bundleWorkspace);
        var byKey = new Dictionary<string, string>();
        foreach (var setting in control.Settings)
        {
            var key = SettingKey(setting);
            byKey[key] = values.TryGetValue(key, out var bySettingKey) ? bySettingKey
                : values.TryGetValue(setting.Id, out var bySettingID) ? bySettingID
                : values.TryGetValue($"{control.Id}.{setting.Id}", out var byQualifiedID) ? byQualifiedID
                : setting.Value ?? "";
        }

        Directory.CreateDirectory(Path.GetDirectoryName(filePath) ?? bundleWorkspace);
        await File.WriteAllTextAsync(filePath, RenderingEngine.SerializeFlatToml(byKey), cancellationToken).ConfigureAwait(false);
        return new ConfigSaveResult(filePath, byKey.Count);
    }

    public static string ConfigPath(ControlSpec control, string? requestedPath, string bundleWorkspace)
    {
        var rawPath = string.IsNullOrWhiteSpace(requestedPath) ? control.ConfigFile?.Path : requestedPath;
        if (string.IsNullOrWhiteSpace(rawPath))
        {
            throw new InvalidOperationException("Choose a settings file path before loading or saving.");
        }

        var expanded = ExpandPathTokens(rawPath, bundleWorkspace);
        return Path.IsPathRooted(expanded) ? expanded : Path.Combine(bundleWorkspace, expanded);
    }

    public static string ExpandPathTokens(string value, string bundleWorkspace, string configPathValue = "")
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var applicationSupport = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return value
            .Replace("{{bundleRoot}}", bundleWorkspace, StringComparison.Ordinal)
            .Replace("{{bundleWorkspace}}", bundleWorkspace, StringComparison.Ordinal)
            .Replace("{{home}}", home, StringComparison.Ordinal)
            .Replace("{{configHome}}", Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), StringComparison.Ordinal)
            .Replace("{{userConfig}}", Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), StringComparison.Ordinal)
            .Replace("{{applicationSupport}}", applicationSupport, StringComparison.Ordinal)
            .Replace("{{appConfig}}", applicationSupport, StringComparison.Ordinal)
            .Replace("{{configPath}}", configPathValue, StringComparison.Ordinal)
            .Replace("{{configDir}}", string.IsNullOrWhiteSpace(configPathValue) ? "" : Path.GetDirectoryName(configPathValue) ?? "", StringComparison.Ordinal);
    }

    private static BundleState NormalizeState(BundleState state) => state with
    {
        LocalizationCode = state.LocalizationCode,
        ConfigFilePaths = state.ConfigFilePaths ?? [],
        FieldValues = state.FieldValues ?? [],
        CheckedOptions = state.CheckedOptions ?? [],
        SelectedPageID = state.SelectedPageID,
        SetupRun = state.SetupRun,
        IconSet = NormalizeIconSet(state.IconSet),
        ColorTheme = NormalizeColorTheme(state.ColorTheme),
        WebUIFont = NormalizeWebUIFont(state.WebUIFont),
    };

    private static string SettingKey(ConfigSettingSpec setting) =>
        string.IsNullOrWhiteSpace(setting.Key) ? setting.Id : setting.Key;
}

public sealed record ConfigSettingBinding(ControlSpec Control, ConfigSettingSpec Setting);
