using GUIForCLIWindows.Core;

namespace GUIForCLIWindows;

public sealed class AppBundleSession
{
    public AppBundleSession(
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
        StartupMessages = startupMessages;
    }

    public string RepoRoot { get; }
    public string BundleRoot { get; }
    public string BundleWorkspace { get; }
    private readonly BundleManifest _sourceManifest;
    public BundleManifest Manifest { get; private set; }
    public BundleState BundleState { get; private set; }
    public Dictionary<string, string> FieldValues { get; }
    public Dictionary<string, string> ConfigValues { get; }
    public Dictionary<string, IReadOnlyList<string>> CheckedOptions { get; }
    public Dictionary<string, string> ConfigFilePaths { get; }
    public IReadOnlyList<LocaleOption> LocaleOptions { get; }
    public IReadOnlyList<string> StartupMessages { get; }

    public static async Task<AppBundleSession> LoadAsync(string repoRoot, string bundleRoot)
    {
        var rawManifest = ManifestLoader.LoadManifestFromRoot(bundleRoot);
        var appPaths = WindowsAppPaths.ForCurrentUser();
        var bundleWorkspace = appPaths.BundleWorkspace(rawManifest.Id);
        appPaths.EnsureBundleDirectories(rawManifest.Id);
        var bundleState = await BundleStateStore.LoadBundleStateAsync(bundleWorkspace);
        var table = ManifestLoader.LoadStringTable(repoRoot, bundleRoot, rawManifest, bundleState.LocalizationCode ?? rawManifest.DefaultLocalizationCode);
        var manifest = ManifestLoader.LocalizeManifest(rawManifest, table);
        var configFilePaths = BundleStateStore.InitialConfigFilePaths(manifest, bundleState);
        var configValues = await BundleStateStore.InitialConfigValuesAsync(manifest, configFilePaths, bundleWorkspace);
        var fieldValues = BundleStateStore.InitialFieldValues(manifest, configValues, bundleState);
        var checkedOptions = BundleStateStore.InitialCheckedOptions(manifest, configValues, bundleState);
        var localeOptions = LoadLocaleOptions(repoRoot, bundleRoot);
        var startupMessages = new List<string>();
        var hydratedManifest = await HydrateDataSourcesAsync(manifest, bundleRoot, fieldValues, configValues, checkedOptions, startupMessages);

        return new AppBundleSession(
            repoRoot,
            bundleRoot,
            bundleWorkspace,
            manifest,
            hydratedManifest,
            bundleState,
            fieldValues,
            configValues,
            checkedOptions,
            configFilePaths,
            localeOptions,
            startupMessages);
    }

    public async Task<IReadOnlyList<string>> RefreshDataSourcesAsync(CancellationToken cancellationToken = default)
    {
        var messages = new List<string>();
        Manifest = await HydrateDataSourcesAsync(_sourceManifest, BundleRoot, FieldValues, ConfigValues, CheckedOptions, messages, cancellationToken);
        return messages;
    }

    public async Task<BundleState> SaveStateAsync(
        string? selectedPageID,
        BundleSetupRunState? setupRun = null,
        CancellationToken cancellationToken = default)
    {
        BundleState = await BundleStateStore.SaveBundleStateAsync(BundleWorkspace, BundleState with
        {
            FieldValues = new Dictionary<string, string>(FieldValues),
            CheckedOptions = CheckedOptions.ToDictionary(pair => pair.Key, pair => pair.Value.ToList()),
            ConfigFilePaths = new Dictionary<string, string>(ConfigFilePaths),
            SelectedPageID = selectedPageID ?? BundleState.SelectedPageID,
            SetupRun = setupRun ?? BundleState.SetupRun,
        }, cancellationToken);
        return BundleState;
    }

    public async Task<BundleState> SavePreferencesAsync(
        string? localizationCode,
        string? colorTheme,
        CancellationToken cancellationToken = default)
    {
        BundleState = await BundleStateStore.SaveBundleStateAsync(BundleWorkspace, BundleState with
        {
            LocalizationCode = string.IsNullOrWhiteSpace(localizationCode) ? null : localizationCode,
            ColorTheme = BundleStateStore.NormalizeColorTheme(colorTheme),
            FieldValues = new Dictionary<string, string>(FieldValues),
            CheckedOptions = CheckedOptions.ToDictionary(pair => pair.Key, pair => pair.Value.ToList()),
            ConfigFilePaths = new Dictionary<string, string>(ConfigFilePaths),
        }, cancellationToken);
        return BundleState;
    }

    private static IReadOnlyList<LocaleOption> LoadLocaleOptions(string repoRoot, string bundleRoot)
    {
        var builtinStrings = Path.Combine(repoRoot, "Resources", "BuiltinStrings");
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

    private static async Task<BundleManifest> HydrateDataSourcesAsync(
        BundleManifest manifest,
        string bundleRoot,
        Dictionary<string, string> fieldValues,
        Dictionary<string, string> configValues,
        Dictionary<string, IReadOnlyList<string>> checkedOptions,
        List<string> startupMessages,
        CancellationToken cancellationToken = default)
    {
        var runtimeService = new BundleRuntimeService(new SimpleProcessRunner());
        var pages = new List<BundlePage>();
        foreach (var page in manifest.Pages)
        {
            var sections = new List<PageSection>();
            foreach (var section in page.Sections)
            {
                var controls = new List<ControlSpec>();
                foreach (var control in section.Controls)
                {
                    if (control.DataSource is null)
                    {
                        controls.Add(control);
                        continue;
                    }

                    try
                    {
                        var payload = await runtimeService.RunDataSourceAsync(
                            control.DataSource,
                            RenderContext(bundleRoot, fieldValues, configValues, checkedOptions),
                            bundleRoot,
                            cancellationToken);
                        controls.Add(RenderingEngine.ApplyDataSourcePayload(control, payload));
                    }
                    catch (Exception error)
                    {
                        controls.Add(control);
                        startupMessages.Add($"Data source failed for {control.Label}: {error.Message}");
                    }
                }

                sections.Add(section with { Controls = controls });
            }

            pages.Add(page with { Sections = sections });
        }

        return manifest with { Pages = pages };
    }

    private static RenderContext RenderContext(
        string bundleRoot,
        Dictionary<string, string> fieldValues,
        Dictionary<string, string> configValues,
        Dictionary<string, IReadOnlyList<string>> checkedOptions) => new()
        {
            BundleRootPath = bundleRoot,
            HomePath = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            FieldValues = fieldValues,
            ConfigValues = configValues,
            CheckedOptions = RenderingEngine.CheckedOptionsForContext(
                checkedOptions.ToDictionary(pair => pair.Key, pair => (IReadOnlyCollection<string>)pair.Value)),
        };
}

public sealed record BundlePageNavigationParameter(AppBundleSession Session, string? PageID);

public sealed record LocaleOption(string Code, string Name)
{
    public override string ToString() => Name;
}
