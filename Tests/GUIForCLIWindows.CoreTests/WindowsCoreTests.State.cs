using GUIForCLIWindows.Core;

internal static partial class WindowsCoreTests
{
static void ComputesWindowsStoragePaths()
{
    var root = Path.Combine(Path.GetTempPath(), "gui-for-cli-tests");
    var paths = new WindowsAppPaths(Path.Combine(root, "local"), Path.Combine(root, "roaming"));
    paths.EnsureBundleDirectories("example/bundle:one");

    Equal(Path.Combine(root, "local", "Bundles", "example_bundle_one"), paths.BundleWorkspace("example/bundle:one"));
    Equal(Path.Combine(root, "local", "Bundles", "example_bundle_one", "state.json"), paths.BundleStateFile("example/bundle:one"));
    Equal(Path.Combine(root, "local", "Bundles", "example_bundle_one", "Config", "settings.toml"), paths.BundleConfigFile("example/bundle:one", "settings.toml"));
    Equal(Path.Combine(root, "roaming", "settings.json"), paths.SettingsFile());
    Equal(true, Directory.Exists(paths.BundleConfigDirectory("example/bundle:one")));
}

static async Task PersistsBundleStateAndConfig()
{
    var workspace = Path.Combine(Path.GetTempPath(), "gui-for-cli-tests", Guid.NewGuid().ToString("N"));
    var manifest = new BundleManifest
    {
        Pages =
        [
            new BundlePage
            {
                Sections =
                [
                    new PageSection
                    {
                        Controls =
                        [
                            new ControlSpec
                            {
                                Id = "output_dir",
                                Kind = "path",
                                Value = "default-out",
                            },
                            new ControlSpec
                            {
                                Id = "flags",
                                Kind = "checkboxGroup",
                                Options = [new ControlOption { Id = "default", Selected = true }],
                            },
                            new ControlSpec
                            {
                                Id = "settings",
                                Kind = "configEditor",
                                ConfigFile = new ConfigFileSpec { Path = "settings.toml" },
                                Settings =
                                [
                                    new ConfigSettingSpec { Id = "threads", Key = "threads", Value = "4" },
                                    new ConfigSettingSpec { Id = "output_dir", Key = "out", Value = "fallback" },
                                    new ConfigSettingSpec { Id = "flags", Key = "flags", Value = "fast,safe" },
                                ],
                            },
                        ],
                    },
                ],
            },
        ],
    };

    var saved = await BundleStateStore.SaveBundleStateAsync(workspace, new BundleState
    {
        LocalizationCode = "en",
        ConfigFilePaths = new Dictionary<string, string> { ["settings"] = "custom.toml" },
        FieldValues = new Dictionary<string, string> { ["output_dir"] = "saved-out" },
        CheckedOptions = new Dictionary<string, List<string>> { ["flags"] = ["saved"] },
        IconSet = "emoji",
        ColorTheme = "dark",
    });
    var loaded = await BundleStateStore.LoadBundleStateAsync(workspace);
    Equal(saved.LocalizationCode, loaded.LocalizationCode);
    Equal("custom.toml", loaded.ConfigFilePaths["settings"]);
    Equal("saved-out", loaded.FieldValues["output_dir"]);
    SequenceEqual(["saved"], loaded.CheckedOptions["flags"]);
    Equal("emoji", loaded.IconSet);
    Equal("dark", loaded.ColorTheme);
    Equal("platform", (await BundleStateStore.SaveBundleStateAsync(workspace, saved with { IconSet = "unknown" })).IconSet);

    var paths = BundleStateStore.InitialConfigFilePaths(manifest, loaded);
    Equal("custom.toml", paths["settings"]);
    await BundleStateStore.SaveConfigAsync(
        RenderingEngine.ConfigEditorControls(manifest)[0],
        paths["settings"],
        new Dictionary<string, string> { ["threads"] = "16", ["out"] = "configured-out", ["flags"] = "alpha,beta" },
        workspace);

    var configValues = await BundleStateStore.InitialConfigValuesAsync(manifest, paths, workspace);
    Equal("16", configValues["settings.threads"]);
    Equal("configured-out", configValues["settings.output_dir"]);
    Equal("configured-out", BundleStateStore.InitialFieldValues(manifest, configValues, loaded)["output_dir"]);
    SequenceEqual(["alpha", "beta"], BundleStateStore.InitialCheckedOptions(manifest, configValues, loaded)["flags"]);

    var loadedConfig = await BundleStateStore.LoadConfigAsync(RenderingEngine.ConfigEditorControls(manifest)[0], "custom.toml", workspace);
    Equal("16", loadedConfig.Values["threads"]);
}

static void HandlesDuplicatePersistedFieldIDs()
{
    var manifest = new BundleManifest
    {
        Pages =
        [
            new BundlePage
            {
                Sections =
                [
                    new PageSection
                    {
                        Controls =
                        [
                            new ControlSpec { Id = "out_dir", Kind = "path", Value = "first" },
                            new ControlSpec { Id = "out_dir", Kind = "path", Value = "second" },
                        ],
                    },
                ],
            },
        ],
    };

    var values = BundleStateStore.InitialFieldValues(manifest, new Dictionary<string, string>(), BundleStateStore.EmptyBundleState());
    Equal("second", values["out_dir"]);
}

static void ValidatesManifestSchemaContract()
{
    var repoRoot = FindRepoRoot();
    ManifestSchemaContract.ValidateSchemaDocument(File.ReadAllText(Path.Combine(
        repoRoot,
        ManifestSchemaContract.SchemaRelativePath.Replace('/', Path.DirectorySeparatorChar))));
    ManifestSchemaContract.ValidateManifestDocument(File.ReadAllText(Path.Combine(repoRoot, "Examples", "WGSExtract", "manifest.json")));
    foreach (var pagePath in Directory.GetFiles(Path.Combine(repoRoot, "Examples", "WGSExtract", "pages"), "*.json"))
    {
        ManifestSchemaContract.ValidatePageDocument(File.ReadAllText(pagePath));
    }
}

static void RejectsMalformedManifestSchemaShapes()
{
    Throws<InvalidDataException>(() => ManifestSchemaContract.ValidateSchemaDocument("[]"));
    Throws<InvalidDataException>(() => ManifestSchemaContract.ValidateManifestDocument("[]"));
    Throws<InvalidDataException>(() => ManifestSchemaContract.ValidatePageDocument("[]"));
}

static void RejectsEscapingConfigPaths()
{
    var workspace = Path.Combine(Path.GetTempPath(), "gui-for-cli-tests", Guid.NewGuid().ToString("N"));
    var control = new ControlSpec
    {
        Id = "settings",
        ConfigFile = new ConfigFileSpec { Path = "settings.toml" },
    };

    Equal(Path.Combine(workspace, "settings.toml"), BundleStateStore.ConfigPath(control, "settings.toml", workspace));
    Throws<InvalidOperationException>(() => BundleStateStore.ConfigPath(control, @"..\outside.toml", workspace));
    Throws<InvalidOperationException>(() => BundleStateStore.ConfigPath(control, @"nested\..\..\outside.toml", workspace));
}

}
