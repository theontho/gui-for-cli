using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Services;

public sealed class DesktopBundleSession
{
    private readonly BundleManifest _sourceManifest;

    private DesktopBundleSession(
        string repoRoot,
        string bundleRoot,
        string bundleWorkspace,
        BundleManifest sourceManifest,
        BundleManifest manifest,
        BundleState bundleState,
        Dictionary<string, string> fieldValues,
        Dictionary<string, string> configValues,
        Dictionary<string, IReadOnlyList<string>> checkedOptions,
        Dictionary<string, string> configFilePaths,
        IReadOnlyList<LocaleOption> localeOptions,
        Dictionary<string, IReadOnlyDictionary<string, string>> sectionValues,
        IReadOnlyList<string> startupMessages)
    {
        RepoRoot = repoRoot;
        BundleRoot = bundleRoot;
        BundleWorkspace = bundleWorkspace;
        _sourceManifest = sourceManifest;
        Manifest = manifest;
        BundleState = bundleState;
        FieldValues = fieldValues;
        ConfigValues = configValues;
        CheckedOptions = checkedOptions;
        ConfigFilePaths = configFilePaths;
        LocaleOptions = localeOptions;
        SectionValues = sectionValues;
        StartupMessages = startupMessages;
    }

    public string RepoRoot { get; }
    public string BundleRoot { get; }
    public string BundleWorkspace { get; }
    public BundleManifest Manifest { get; private set; }
    public BundleState BundleState { get; private set; }
    public Dictionary<string, string> FieldValues { get; }
    public Dictionary<string, string> ConfigValues { get; }
    public Dictionary<string, IReadOnlyList<string>> CheckedOptions { get; }
    public Dictionary<string, string> ConfigFilePaths { get; }
    public IReadOnlyList<LocaleOption> LocaleOptions { get; }
    public Dictionary<string, IReadOnlyDictionary<string, string>> SectionValues { get; private set; }
    public IReadOnlyList<string> StartupMessages { get; }

    public static async Task<DesktopBundleSession> LoadAsync(string repoRoot, string bundleRoot, CancellationToken cancellationToken = default)
    {
        var rawManifest = ManifestLoader.LoadManifestFromRoot(bundleRoot);
        var appPaths = AvaloniaAppPaths.ForCurrentUser();
        var bundleWorkspace = appPaths.BundleWorkspace(rawManifest.Id);
        appPaths.EnsureBundleDirectories(rawManifest.Id);

        var bundleState = await BundleStateStore.LoadBundleStateAsync(bundleWorkspace, cancellationToken).ConfigureAwait(false);
        var locale = bundleState.LocalizationCode ?? rawManifest.DefaultLocalizationCode;
        var table = ManifestLoader.LoadStringTable(repoRoot, bundleRoot, rawManifest, locale);
        var manifest = ManifestLoader.LocalizeManifest(rawManifest, table);
        var configFilePaths = BundleStateStore.InitialConfigFilePaths(manifest, bundleState);
        var configValues = await BundleStateStore.InitialConfigValuesAsync(manifest, configFilePaths, bundleWorkspace, cancellationToken).ConfigureAwait(false);
        var fieldValues = BundleStateStore.InitialFieldValues(manifest, configValues, bundleState);
        var checkedOptions = BundleStateStore.InitialCheckedOptions(manifest, configValues, bundleState);
        var startupMessages = new List<string>();
        var hydrated = await HydrateDataSourcesAsync(
            manifest,
            bundleRoot,
            bundleWorkspace,
            fieldValues,
            configValues,
            checkedOptions,
            startupMessages,
            cancellationToken).ConfigureAwait(false);

        return new DesktopBundleSession(
            repoRoot,
            bundleRoot,
            bundleWorkspace,
            manifest,
            hydrated.Manifest,
            bundleState,
            fieldValues,
            configValues,
            checkedOptions,
            configFilePaths,
            LoadLocaleOptions(repoRoot, bundleRoot),
            hydrated.SectionValues,
            startupMessages);
    }

    public async Task<IReadOnlyList<string>> RefreshDataSourcesAsync(CancellationToken cancellationToken = default)
    {
        var messages = new List<string>();
        var hydrated = await HydrateDataSourcesAsync(
            _sourceManifest,
            BundleRoot,
            BundleWorkspace,
            FieldValues,
            ConfigValues,
            CheckedOptions,
            messages,
            cancellationToken).ConfigureAwait(false);
        Manifest = hydrated.Manifest;
        SectionValues = hydrated.SectionValues;
        return messages;
    }

    public async Task SaveStateAsync(string? selectedPageID, BundleSetupRunState? setupRun = null, CancellationToken cancellationToken = default)
    {
        BundleState = await BundleStateStore.SaveBundleStateAsync(BundleWorkspace, BundleState with
        {
            FieldValues = new Dictionary<string, string>(FieldValues),
            CheckedOptions = CheckedOptions.ToDictionary(pair => pair.Key, pair => pair.Value.ToList()),
            ConfigFilePaths = new Dictionary<string, string>(ConfigFilePaths),
            SelectedPageID = selectedPageID ?? BundleState.SelectedPageID,
            SetupRun = setupRun ?? BundleState.SetupRun,
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task SavePreferencesAsync(string? localizationCode, string? colorTheme, CancellationToken cancellationToken = default)
    {
        BundleState = await BundleStateStore.SaveBundleStateAsync(BundleWorkspace, BundleState with
        {
            LocalizationCode = string.IsNullOrWhiteSpace(localizationCode) ? null : localizationCode,
            ColorTheme = BundleStateStore.NormalizeColorTheme(colorTheme),
            FieldValues = new Dictionary<string, string>(FieldValues),
            CheckedOptions = CheckedOptions.ToDictionary(pair => pair.Key, pair => pair.Value.ToList()),
            ConfigFilePaths = new Dictionary<string, string>(ConfigFilePaths),
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task SaveConfigEditorAsync(ControlSpec control, CancellationToken cancellationToken = default)
    {
        if (control.ConfigFile is null)
        {
            return;
        }

        var requestedPath = ConfigFilePaths.TryGetValue(control.Id, out var savedPath) ? savedPath : control.ConfigFile.Path;
        await BundleStateStore.SaveConfigAsync(control, requestedPath, ConfigValues, BundleWorkspace, cancellationToken).ConfigureAwait(false);
        await SaveStateAsync(BundleState.SelectedPageID, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    public RenderContext CommandContext(IReadOnlyDictionary<string, string>? sectionValues = null, IReadOnlyDictionary<string, string>? rowValues = null)
    {
        var fieldValues = Merge(FieldValues, sectionValues);
        var configValues = Merge(ConfigAliases(), ConfigValues, FieldValues, sectionValues);
        return new RenderContext
        {
            BundleRootPath = BundleRoot,
            BundleWorkspacePath = BundleWorkspace,
            HomePath = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            FieldValues = fieldValues,
            ConfigValues = configValues,
            RowValues = rowValues ?? new Dictionary<string, string>(),
            CheckedOptions = RenderingEngine.CheckedOptionsForContext(CheckedOptions.ToDictionary(pair => pair.Key, pair => (IReadOnlyCollection<string>)pair.Value)),
        };
    }

    public IReadOnlyDictionary<string, string> SectionContextValues(string sectionID) =>
        SectionValues.TryGetValue(sectionID, out var values) ? values : new Dictionary<string, string>();

    private static async Task<HydratedManifest> HydrateDataSourcesAsync(
        BundleManifest manifest,
        string bundleRoot,
        string bundleWorkspace,
        Dictionary<string, string> fieldValues,
        Dictionary<string, string> configValues,
        Dictionary<string, IReadOnlyList<string>> checkedOptions,
        List<string> startupMessages,
        CancellationToken cancellationToken)
    {
        var runtimeService = new BundleRuntimeService(new SimpleProcessRunner());
        var sectionValues = new Dictionary<string, IReadOnlyDictionary<string, string>>(StringComparer.Ordinal);
        var pages = new List<BundlePage>();

        foreach (var page in manifest.Pages)
        {
            var sections = new List<PageSection>();
            foreach (var section in page.Sections)
            {
                var valuesForSection = await LoadSectionValuesAsync(runtimeService, section, bundleRoot, bundleWorkspace, fieldValues, configValues, checkedOptions, startupMessages, cancellationToken).ConfigureAwait(false);
                if (valuesForSection.Count > 0)
                {
                    sectionValues[section.Id] = valuesForSection;
                }

                var controls = new List<ControlSpec>();
                foreach (var control in section.Controls)
                {
                    controls.Add(await HydrateControlAsync(runtimeService, control, bundleRoot, bundleWorkspace, fieldValues, configValues, checkedOptions, valuesForSection, startupMessages, cancellationToken).ConfigureAwait(false));
                }

                sections.Add(section with { Controls = controls });
            }

            pages.Add(page with { Sections = sections });
        }

        return new HydratedManifest(manifest with { Pages = pages }, sectionValues);
    }

    private static async Task<Dictionary<string, string>> LoadSectionValuesAsync(
        BundleRuntimeService runtimeService,
        PageSection section,
        string bundleRoot,
        string bundleWorkspace,
        Dictionary<string, string> fieldValues,
        Dictionary<string, string> configValues,
        Dictionary<string, IReadOnlyList<string>> checkedOptions,
        List<string> startupMessages,
        CancellationToken cancellationToken)
    {
        if (section.DataSource is null)
        {
            return [];
        }

        try
        {
            var payload = await runtimeService.RunDataSourceAsync(
                section.DataSource,
                RenderContext(bundleRoot, bundleWorkspace, fieldValues, configValues, checkedOptions),
                bundleRoot,
                cancellationToken).ConfigureAwait(false);
            return payload.Values ?? [];
        }
        catch (Exception error)
        {
            startupMessages.Add($"Data source failed for {section.Title ?? section.Id}: {error.Message}");
            return [];
        }
    }

    private static async Task<ControlSpec> HydrateControlAsync(
        BundleRuntimeService runtimeService,
        ControlSpec control,
        string bundleRoot,
        string bundleWorkspace,
        Dictionary<string, string> fieldValues,
        Dictionary<string, string> configValues,
        Dictionary<string, IReadOnlyList<string>> checkedOptions,
        IReadOnlyDictionary<string, string> sectionValues,
        List<string> startupMessages,
        CancellationToken cancellationToken)
    {
        var context = RenderContext(bundleRoot, bundleWorkspace, Merge(fieldValues, sectionValues), Merge(configValues, fieldValues, sectionValues), checkedOptions);
        var next = control;
        if (control.Kind == "configEditor" && control.Settings.Any(setting => setting.DataSource is not null))
        {
            next = control with { Settings = await HydrateSettingsAsync(runtimeService, control, context, bundleRoot, startupMessages, cancellationToken).ConfigureAwait(false) };
        }

        if (next.DataSource is null)
        {
            return next;
        }

        try
        {
            var payload = await runtimeService.RunDataSourceAsync(next.DataSource, context, bundleRoot, cancellationToken).ConfigureAwait(false);
            return RenderingEngine.ApplyDataSourcePayload(next, payload);
        }
        catch (Exception error)
        {
            startupMessages.Add($"Data source failed for {next.Label}: {error.Message}");
            return next;
        }
    }

    private static async Task<List<ConfigSettingSpec>> HydrateSettingsAsync(
        BundleRuntimeService runtimeService,
        ControlSpec control,
        RenderContext context,
        string bundleRoot,
        List<string> startupMessages,
        CancellationToken cancellationToken)
    {
        var settings = new List<ConfigSettingSpec>();
        foreach (var setting in control.Settings)
        {
            if (setting.DataSource is null)
            {
                settings.Add(setting);
                continue;
            }

            try
            {
                var payload = await runtimeService.RunDataSourceAsync(setting.DataSource, context, bundleRoot, cancellationToken).ConfigureAwait(false);
                settings.Add(setting with { Options = payload.Options ?? setting.Options });
            }
            catch (Exception error)
            {
                startupMessages.Add($"Data source failed for {setting.Label}: {error.Message}");
                settings.Add(setting);
            }
        }

        return settings;
    }

    private static RenderContext RenderContext(
        string bundleRoot,
        string bundleWorkspace,
        Dictionary<string, string> fieldValues,
        Dictionary<string, string> configValues,
        Dictionary<string, IReadOnlyList<string>> checkedOptions) => new()
        {
            BundleRootPath = bundleRoot,
            BundleWorkspacePath = bundleWorkspace,
            HomePath = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            FieldValues = fieldValues,
            ConfigValues = configValues,
            CheckedOptions = RenderingEngine.CheckedOptionsForContext(checkedOptions.ToDictionary(pair => pair.Key, pair => (IReadOnlyCollection<string>)pair.Value)),
        };

    private static Dictionary<string, string> Merge(params IReadOnlyDictionary<string, string>?[] sources)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var source in sources)
        {
            if (source is null)
            {
                continue;
            }

            foreach (var (key, value) in source)
            {
                values[key] = value;
            }
        }

        return values;
    }

    private Dictionary<string, string> ConfigAliases()
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var control in RenderingEngine.ConfigEditorControls(Manifest))
        {
            foreach (var setting in control.Settings)
            {
                var qualified = RenderingEngine.ConfigValueKey(control, setting);
                if (!ConfigValues.TryGetValue(qualified, out var value))
                {
                    continue;
                }

                values[setting.Id] = value;
                if (!string.IsNullOrWhiteSpace(setting.Key))
                {
                    values[setting.Key] = value;
                    values[$"config.{setting.Key}"] = value;
                }
            }
        }

        return values;
    }

    private static IReadOnlyList<LocaleOption> LoadLocaleOptions(string repoRoot, string bundleRoot)
    {
        var builtinStrings = Path.Combine(repoRoot, "platform", "apple", "shared", "Sources", "GUIForCLICore", "Resources", "BuiltinStrings");
        var bundleStrings = Path.Combine(bundleRoot, "strings");
        var codes = FilesIfDirectoryExists(builtinStrings, "strings.*.toml")
            .Concat(FilesIfDirectoryExists(bundleStrings, "strings.*.toml"))
            .Select(path => Path.GetFileNameWithoutExtension(path)["strings.".Length..])
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToList();

        return codes.Select(code =>
        {
            var table = ManifestLoader.LoadStringTable(repoRoot, bundleRoot, new BundleManifest { DefaultLocalizationCode = "en" }, code);
            var name = table.TryGetValue("language.name", out var languageName) ? languageName : code;
            return new LocaleOption(code, name);
        }).ToList();
    }

    private static IEnumerable<string> FilesIfDirectoryExists(string directory, string searchPattern) =>
        Directory.Exists(directory) ? Directory.GetFiles(directory, searchPattern) : [];

    private sealed record HydratedManifest(BundleManifest Manifest, Dictionary<string, IReadOnlyDictionary<string, string>> SectionValues);
}

public sealed record LocaleOption(string Code, string Name)
{
    public override string ToString() => Name;
}
