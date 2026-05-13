using GUIForCLIWindows.Core;

var tests = new (string Name, Func<Task> Body)[]
{
    ("parses flat localization TOML with comments and multiline values", Sync(ParseLocalizationToml)),
    ("computes initial field, option, and config state", Sync(ComputesInitialState)),
    ("renders commands with required and optional placeholders", Sync(RenderCommands)),
    ("hydrates list rows from item values and templates", Sync(HydrateRows)),
    ("builds row context for action rendering", Sync(BuildsRowContext)),
    ("evaluates numeric action conditions", Sync(NumericActionConditions)),
    ("evaluates action visibility and disabled reasons", Sync(ActionVisibilityAndDisabledReasons)),
    ("evaluates disk precheck arithmetic expressions", Sync(NumericExpressions)),
    ("returns NaN for malformed numeric expressions", Sync(MalformedNumericExpressions)),
    ("round trips flat TOML config values", Sync(RoundTripsFlatToml)),
    ("parses quoted TOML keys with separators safely", Sync(ParsesQuotedTomlKeys)),
    ("computes path extension from Windows paths", Sync(ComputesWindowsPathExtension)),
    ("applies data source payload with WebUI row precedence", Sync(AppliesDataSourcePayload)),
    ("localizes nested manifest values", Sync(LocalizesNestedManifestValues)),
    ("validates manifest schema contract", Sync(ValidatesManifestSchemaContract)),
    ("computes Windows app storage paths", Sync(ComputesWindowsStoragePaths)),
    ("persists bundle state and config TOML", PersistsBundleStateAndConfig),
    ("handles duplicate persisted field IDs", Sync(HandlesDuplicatePersistedFieldIDs)),
    ("routes Windows commands without shell quoting", Sync(RoutesWindowsCommands)),
    ("routes shell scripts to PowerShell siblings", RoutesShellScriptsToPowerShellSiblings),
    ("maps semantic icons to Fluent glyphs", Sync(MapsSemanticIconsToFluentGlyphs)),
    ("parses bundle icon maps", Sync(ParsesBundleIconMaps)),
    ("builds Windows setup commands", Sync(BuildsWindowsSetupCommands)),
    ("exposes Windows process hardening primitives", Sync(ExposesWindowsProcessHardeningPrimitives)),
    ("runs bundle data source and file state", RunsBundleDataSourceAndFileState),
    ("resolves relative file state paths from workspace before bundle root", Sync(ResolvesFileStateFromWorkspaceFirst)),
    ("runs a simple redirected process", RunsSimpleRedirectedProcess),
    ("loads and localizes WGSExtract split manifest", Sync(LoadsAndLocalizesWgsExtract)),
};

var failed = 0;
foreach (var (name, body) in tests)
{
    try
    {
        await body();
        Console.WriteLine($"PASS {name}");
    }
    catch (Exception error)
    {
        failed += 1;
        Console.Error.WriteLine($"FAIL {name}");
        Console.Error.WriteLine(error);
    }
}

static Func<Task> Sync(Action body) => () =>
{
    body();
    return Task.CompletedTask;
};

if (failed > 0)
{
    Environment.Exit(1);
}

static void ParseLocalizationToml()
{
    var table = LocalizationEngine.ParseTomlStrings("\"language.name\" = \"English\" # translator hint\nkey = \"\"\"\nfirst\nsecond\n\"\"\"\n");
    Equal("English", table["language.name"]);
    Equal("first\nsecond", table["key"]);
}

static void RenderCommands()
{
    var command = new CommandSpec
    {
        Executable = "tool",
        Arguments = ["run", "{{input}}"],
        OptionalArguments = [["--label", "{{label}}"], ["--missing", "{{missing}}"]],
    };
    var context = new RenderContext
    {
        FieldValues = new Dictionary<string, string> { ["input"] = "file name.bam", ["label"] = "sample" },
    };

    SequenceEqual(Array.Empty<string>(), RenderingEngine.MissingPlaceholders(command, context));
    Equal("tool run 'file name.bam' --label sample", RenderingEngine.DisplayCommand(command, context));
}

static void ComputesInitialState()
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
                            new ControlSpec { Id = "input", Kind = "text", Value = "sample" },
                            new ControlSpec
                            {
                                Id = "flags",
                                Kind = "checkboxGroup",
                                Options =
                                [
                                    new ControlOption { Id = "fast", Title = "Fast", Selected = true },
                                    new ControlOption { Id = "safe", Title = "Safe" },
                                ],
                            },
                            new ControlSpec
                            {
                                Id = "settings",
                                Kind = "configEditor",
                                Settings = [new ConfigSettingSpec { Id = "threads", Value = "8" }],
                            },
                        ],
                    },
                ],
            },
        ],
    };

    Equal("sample", RenderingEngine.InitialFieldValues(manifest)["input"]);
    Equal(true, RenderingEngine.InitialCheckedOptions(manifest)["flags"].Contains("fast"));
    Equal("8", RenderingEngine.InitialConfigValues(manifest)["settings.threads"]);
    Equal("a,b", RenderingEngine.CheckedOptionsForContext(new Dictionary<string, IReadOnlyCollection<string>>
    {
        ["flags"] = ["b", "a"],
    })["flags"]);
}

static void HydrateRows()
{
    var rows = RenderingEngine.HydrateRows(new ControlSpec
    {
        Columns = [new ListColumnSpec { Id = "name", Title = "Name" }],
        RowTemplate = new ListRowSpec
        {
            Id = "{{id}}",
            Title = "{{name}}",
            Values = new Dictionary<string, string> { ["build"] = "{{build}}" },
            Status = "{{status}}",
        },
        Items =
        [
            new ListItemSpec
            {
                Values = new Dictionary<string, string>
                {
                    ["id"] = "hg38",
                    ["name"] = "GRCh38",
                    ["build"] = "GRCh38",
                    ["status"] = "installed",
                },
            },
        ],
    });

    Equal(1, rows.Count);
    Equal("hg38", rows[0].Id);
    Equal("GRCh38", rows[0].Title);
    Equal("GRCh38", rows[0].Values["build"]);
    Equal("installed", rows[0].Status);
    Equal(0, rows[0].Tags.Count);
    Equal(null, rows[0].Tooltip);
}

static void BuildsRowContext()
{
    var context = RenderingEngine.RowContext(new RenderContext
    {
        FieldValues = new Dictionary<string, string> { ["input"] = "sample" },
    }, new ListRowSpec
    {
        Id = "row-1",
        Title = "Sample Row",
        Status = "installed",
        Values = new Dictionary<string, string> { ["path"] = @"C:\data\sample.bam" },
    });

    Equal("sample", context.FieldValues["input"]);
    Equal("row-1", context.RowValues["id"]);
    Equal("Sample Row", context.RowValues["title"]);
    Equal("installed", context.RowValues["status"]);
    Equal(@"C:\data\sample.bam", context.RowValues["path"]);
}

static void NumericActionConditions()
{
    var matches = RenderingEngine.ConditionMatches(
        new ActionConditionSpec { Placeholder = "size", GreaterThanOrEqual = "2 * 5" },
        new RenderContext { FieldValues = new Dictionary<string, string> { ["size"] = "10" } });
    Equal(true, matches);
}

static void ActionVisibilityAndDisabledReasons()
{
    var action = new ActionSpec
    {
        Title = "Run",
        VisibleWhen = [new ActionConditionSpec { Placeholder = "mode", EqualTo = "ready" }],
        DisabledWhen = [new ActionConditionSpec { Placeholder = "disk", LessThan = "5" }],
        DisabledTooltip = "Only {{disk}} GB free",
    };
    var context = new RenderContext
    {
        FieldValues = new Dictionary<string, string> { ["mode"] = "ready", ["disk"] = "4" },
    };

    Equal(true, RenderingEngine.IsActionVisible(action, context));
    Equal("Only 4 GB free", RenderingEngine.DisabledReason(action, context));
}

static void NumericExpressions()
{
    Equal(9.0, RenderingEngine.EvaluateNumeric("1.5 * 6"));
    Equal(20.0, RenderingEngine.EvaluateNumeric("(2 + 3) * 4"));
}

static void MalformedNumericExpressions()
{
    Equal(true, double.IsNaN(RenderingEngine.EvaluateNumeric("1..2")));
    Equal(true, double.IsNaN(RenderingEngine.EvaluateNumeric("bad")));
}

static void RoundTripsFlatToml()
{
    var text = RenderingEngine.SerializeFlatToml(new Dictionary<string, string>
    {
        ["output_dir"] = "/tmp/out",
        ["quoted"] = "a \"value\"",
    });
    var parsed = RenderingEngine.ParseFlatToml(text);
    Equal("/tmp/out", parsed["output_dir"]);
    Equal("a \"value\"", parsed["quoted"]);
}

static void ParsesQuotedTomlKeys()
{
    var parsed = RenderingEngine.ParseFlatToml("\"a=b\" = \"value\"\n\"__proto__\" = \"safe\"\n");
    Equal("value", parsed["a=b"]);
    Equal("safe", parsed["__proto__"]);
}

static void ComputesWindowsPathExtension()
{
    var context = new RenderContext
    {
        FieldValues = new Dictionary<string, string> { ["input"] = @"C:\data\sample.BAM" },
    };
    Equal("bam", RenderingEngine.ContextValue(context, "input.pathExtension"));
}

static void AppliesDataSourcePayload()
{
    var control = new ControlSpec
    {
        Id = "library",
        Kind = "libraryList",
        Items = [new ListItemSpec { Values = new Dictionary<string, string> { ["id"] = "old" } }],
    };
    var next = RenderingEngine.ApplyDataSourcePayload(control, new DataSourcePayload
    {
        Rows = [new ListRowSpec { Id = "row-1", Title = "Row" }],
    });
    Equal(1, next.Rows.Count);
    Equal("row-1", next.Rows[0].Id);
    Equal(0, next.Items.Count);
}

static void LoadsAndLocalizesWgsExtract()
{
    var repoRoot = FindRepoRoot();
    var bundleRoot = Path.Combine(repoRoot, "examples", "WGSExtract");
    var manifest = ManifestLoader.LoadManifestFromRoot(bundleRoot);
    Equal("wgs-extract", manifest.Id);
    Equal("Assets/icon.png", manifest.IconPath);
    Equal(9, manifest.Pages.Count);
    Equal(9, manifest.PageFiles.Count);
    Equal(true, RenderingEngine.AllControls(manifest).Count > 20);

    var table = ManifestLoader.LoadStringTable(repoRoot, bundleRoot, manifest, "en");
    var localized = ManifestLoader.LocalizeManifest(manifest, table);
    Equal("WGS Extract", localized.DisplayName);
    Equal("FASTQ", localized.Pages[0].Title);
    Equal("Convert", localized.Pages[0].SidebarGroup);
    Equal("FASTQ R1", localized.Pages[0].Sections[0].Controls[0].Label);
}

static void LocalizesNestedManifestValues()
{
    var table = new Dictionary<string, string>
    {
        ["control.label"] = "Control",
        ["item.name"] = "Localized item",
        ["setting.label"] = "Setting",
        ["setting.placeholder"] = "Enter value",
        ["option.title"] = "Choice",
        ["option.group"] = "Group",
        ["confirm.title"] = "Confirm",
        ["confirm.message"] = "Are you sure?",
        ["confirm.ok"] = "Run",
        ["confirm.cancel"] = "Cancel",
        ["confirm.prompt"] = "Type value",
    };
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
                                Label = "control.label",
                                Items = [new ListItemSpec { Values = new Dictionary<string, string> { ["name"] = "item.name" } }],
                                Settings =
                                [
                                    new ConfigSettingSpec
                                    {
                                        Label = "setting.label",
                                        Placeholder = "setting.placeholder",
                                        Options = [new ControlOption { Title = "option.title", Group = "option.group" }],
                                    },
                                ],
                                RowActions =
                                [
                                    new ActionSpec
                                    {
                                        Title = "confirm.ok",
                                        Confirm = new ConfirmationSpec
                                        {
                                            Title = "confirm.title",
                                            Message = "confirm.message",
                                            ConfirmButtonTitle = "confirm.ok",
                                            CancelButtonTitle = "confirm.cancel",
                                            Prompt = "confirm.prompt",
                                        },
                                    },
                                ],
                            },
                        ],
                    },
                ],
            },
        ],
    };

    var control = ManifestLoader.LocalizeManifest(manifest, table).Pages[0].Sections[0].Controls[0];
    Equal("Control", control.Label);
    Equal("Localized item", control.Items[0].Values!["name"]);
    Equal("Setting", control.Settings[0].Label);
    Equal("Enter value", control.Settings[0].Placeholder);
    Equal("Choice", control.Settings[0].Options[0].Title);
    Equal("Group", control.Settings[0].Options[0].Group);
    Equal("Confirm", control.RowActions[0].Confirm!.Title);
    Equal("Are you sure?", control.RowActions[0].Confirm!.Message);
    Equal("Run", control.RowActions[0].Confirm!.ConfirmButtonTitle);
    Equal("Cancel", control.RowActions[0].Confirm!.CancelButtonTitle);
    Equal("Type value", control.RowActions[0].Confirm!.Prompt);
}

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
        SelectedPageID = "settings",
        SetupRun = new BundleSetupRunState
        {
            Status = "ok",
            Results = [new BundleSetupStepRunState { Id = "pixi", Label = "Pixi", Kind = "pixi", Status = "ok", ExitCode = 0 }],
            CompletedAt = "2026-05-09T00:00:00.0000000Z",
        },
        IconSet = "emoji",
        ColorTheme = "dark",
        WebUIFont = "mono",
    });
    var loaded = await BundleStateStore.LoadBundleStateAsync(workspace);
    Equal(saved.LocalizationCode, loaded.LocalizationCode);
    Equal("custom.toml", loaded.ConfigFilePaths["settings"]);
    Equal("saved-out", loaded.FieldValues["output_dir"]);
    SequenceEqual(["saved"], loaded.CheckedOptions["flags"]);
    Equal("settings", loaded.SelectedPageID);
    Equal("ok", loaded.SetupRun!.Status);
    Equal("pixi", loaded.SetupRun.Results[0].Id);
    Equal("emoji", loaded.IconSet);
    Equal("dark", loaded.ColorTheme);
    Equal("mono", loaded.WebUIFont);
    Equal("platform", (await BundleStateStore.SaveBundleStateAsync(workspace, saved with { IconSet = "unknown" })).IconSet);
    Equal("system", (await BundleStateStore.SaveBundleStateAsync(workspace, saved with { WebUIFont = "unknown" })).WebUIFont);

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

    await BundleStateStore.SaveConfigAsync(
        RenderingEngine.ConfigEditorControls(manifest)[0],
        paths["settings"],
        new Dictionary<string, string> { ["threads"] = "24", ["out"] = "configured-out-2", ["flags"] = "gamma" },
        workspace);
    var overwrittenConfig = await BundleStateStore.LoadConfigAsync(RenderingEngine.ConfigEditorControls(manifest)[0], "custom.toml", workspace);
    Equal("24", overwrittenConfig.Values["threads"]);
    Equal(false, Directory.EnumerateFiles(workspace, "*.tmp", SearchOption.AllDirectories).Any());
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
    ManifestSchemaContract.ValidateManifestDocument(File.ReadAllText(Path.Combine(repoRoot, "examples", "WGSExtract", "manifest.json")));
    foreach (var pagePath in Directory.GetFiles(Path.Combine(repoRoot, "examples", "WGSExtract", "pages"), "*.json"))
    {
        ManifestSchemaContract.ValidatePageDocument(File.ReadAllText(pagePath));
    }
}

static void RoutesWindowsCommands()
{
    var direct = WindowsCommandRouter.StartInfo(new ProcessExecutionRequest
    {
        Command = new RenderedCommand("tool.exe", ["a value", "--flag"]),
    });
    Equal("tool.exe", direct.FileName);
    Equal("a value", direct.ArgumentList[0]);
    Equal("--flag", direct.ArgumentList[1]);

    var batch = WindowsCommandRouter.StartInfo(new ProcessExecutionRequest
    {
        Command = new RenderedCommand("setup.cmd", ["arg"]),
    });
    Equal("cmd.exe", batch.FileName);
    Equal("/d", batch.ArgumentList[0]);
    Equal("/c", batch.ArgumentList[1]);
    Equal("setup.cmd", batch.ArgumentList[2]);
    Equal("arg", batch.ArgumentList[3]);

    var python = WindowsCommandRouter.StartInfo(new ProcessExecutionRequest
    {
        Command = new RenderedCommand("source.py", ["options"]),
    });
    Equal("python.exe", python.FileName);
    Equal("source.py", python.ArgumentList[0]);
    Equal("options", python.ArgumentList[1]);

    Environment.SetEnvironmentVariable("GUI_FOR_CLI_POWERSHELL", "powershell.exe");
    try
    {
        var script = WindowsCommandRouter.StartInfo(new ProcessExecutionRequest
        {
            Command = new RenderedCommand("setup.ps1", ["-Mode", "quiet"]),
        });
        Equal("powershell.exe", script.FileName);
        Equal("-NoProfile", script.ArgumentList[0]);
        Equal("-File", script.ArgumentList[4]);
        Equal("setup.ps1", script.ArgumentList[5]);
        Equal("-Mode", script.ArgumentList[6]);
        Equal("quiet", script.ArgumentList[7]);
    }
    finally
    {
        Environment.SetEnvironmentVariable("GUI_FOR_CLI_POWERSHELL", null);
    }
}

static async Task RoutesShellScriptsToPowerShellSiblings()
{
    var root = Path.Combine(Path.GetTempPath(), "gui-for-cli-routing-tests", Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(root);
    var shellScript = Path.Combine(root, "tool.sh");
    var powerShellScript = Path.Combine(root, "tool.ps1");
    await File.WriteAllTextAsync(shellScript, "#!/bin/sh\n");
    await File.WriteAllTextAsync(powerShellScript, "'ps1:' + ($args -join ',')\n");

    Environment.SetEnvironmentVariable("GUI_FOR_CLI_POWERSHELL", "pwsh.exe");
    try
    {
        var info = WindowsCommandRouter.StartInfo(new ProcessExecutionRequest
        {
            Command = new RenderedCommand(shellScript, ["a", "b"]),
        });
        Equal("pwsh.exe", info.FileName);
        Equal(powerShellScript, info.ArgumentList[5]);

        var result = await new SimpleProcessRunner().RunAsync(new ProcessExecutionRequest
        {
            Command = new RenderedCommand(shellScript, ["a", "b"]),
            Timeout = TimeSpan.FromSeconds(10),
        });
        Equal(0, result.ExitCode);
        Equal("ps1:a,b", result.StandardOutput.Trim());
    }
    finally
    {
        Environment.SetEnvironmentVariable("GUI_FOR_CLI_POWERSHELL", null);
    }
}

static void MapsSemanticIconsToFluentGlyphs()
{
    var iconMap = BundleIconMap.Parse("""
        [windows]
        "settings" = "\uE713"
        "terminal" = "\uE756"
        "fasta" = "\uECAA"
        """);
    Equal("\uE713", WindowsIconMapper.GlyphFor("settings", iconMap));
    Equal("\uE756", WindowsIconMapper.GlyphFor("terminal", iconMap));
    Equal("\uECAA", WindowsIconMapper.GlyphFor("fasta", iconMap));
    Equal("\uECAA", WindowsIconMapper.GlyphFor("missing-symbol", iconMap));
}

static void ParsesBundleIconMaps()
{
    var iconMap = BundleIconMap.Parse("""
        [sf-symbols]
        "fasta" = "point.3.connected.trianglepath.dotted"

        [windows]
        "download" = "\uE896"
        "refresh" = " \uE72C"

        [bootstrap]
        "warning" = "exclamation-triangle-fill"

        [emoji]
        "warning" = "⚠️"
        """);

    Equal("point.3.connected.trianglepath.dotted", iconMap.Resolve(BundleIconMap.SfSymbolsSource, "fasta"));
    Equal("\uE896", iconMap.Resolve(BundleIconMap.WindowsSource, "download"));
    Equal(" \uE72C", iconMap.Resolve(BundleIconMap.WindowsSource, "refresh"));
    Equal("exclamation-triangle-fill", iconMap.Resolve(BundleIconMap.BootstrapSource, "warning"));
    Equal("⚠️", iconMap.Resolve(BundleIconMap.EmojiSource, "warning"));
}

static void BuildsWindowsSetupCommands()
{
    Equal(true, WindowsSetupKinds.IsWindowsNative(WindowsSetupKinds.PowershellScript));
    var script = WindowsSetupKinds.CommandFor(new SetupStepSpec
    {
        Kind = WindowsSetupKinds.PowershellScript,
        Script = "scripts/setup.ps1",
    });
    Equal("scripts/setup.ps1", script!.Executable);

    var package = WindowsSetupKinds.CommandFor(new SetupStepSpec
    {
        Kind = WindowsSetupKinds.WingetPackage,
        PackageId = "Prefix.Tool",
    });
    Equal("winget.exe", package!.Executable);
    SequenceEqual(["list", "--id", "Prefix.Tool", "--exact"], package.Arguments);

    var pixi = WindowsSetupKinds.CommandFor(new SetupStepSpec { Kind = WindowsSetupKinds.Pixi });
    Equal("pixi.exe", pixi!.Executable);
    SequenceEqual(["--version"], pixi.Arguments);

    var pixiRun = WindowsSetupKinds.CommandFor(new SetupStepSpec { Kind = "pixiRun", Value = "wgsextract", Arguments = ["deps", "check"] });
    Equal("pixi.exe", pixiRun!.Executable);
    SequenceEqual(["run", "wgsextract", "deps", "check"], pixiRun.Arguments);
}

static void ExposesWindowsProcessHardeningPrimitives()
{
    Equal(OperatingSystem.IsWindows(), WindowsJobObject.IsSupported);
    if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 17763))
    {
        Equal(true, ConPtyProcessRunner.IsAvailable);
    }
}

static async Task RunsBundleDataSourceAndFileState()
{
    var root = Path.Combine(Path.GetTempPath(), "gui-for-cli-runtime-tests", Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(Path.Combine(root, "scripts"));
    var script = Path.Combine(root, "scripts", "options.cmd");
    await File.WriteAllTextAsync(script, "@echo {^\"options^\":[{^\"id^\":^\"hg38^\",^\"title^\":^\"GRCh38^\"}]}\r\n");
    var data = Path.Combine(root, "sample.sorted.bam");
    await File.WriteAllTextAsync(data, "bam");
    await File.WriteAllTextAsync($"{data}.bai", "index");

    var service = new BundleRuntimeService(new SimpleProcessRunner());
    var payload = await service.RunDataSourceAsync(new DataSourceSpec
    {
        Path = "scripts/options.cmd",
        Arguments = ["{{mode}}"],
    }, new RenderContext
    {
        BundleRootPath = root,
        FieldValues = new Dictionary<string, string> { ["mode"] = "options" },
    }, root);
    Equal("hg38", payload.Options![0].Id);

    var state = await service.FileStateValuesAsync(new RenderContext
    {
        FieldValues = new Dictionary<string, string> { ["alignment"] = data },
    }, root);
    Equal("true", state["alignment.exists"]);
    Equal("bam", state["alignment.pathExtension"]);
    Equal("true", state["alignment.isIndexed"]);
    Equal("true", state["alignment.isSorted"]);
}

static void ResolvesFileStateFromWorkspaceFirst()
{
    var root = Path.Combine(FindRepoRoot(), "tmp", "core-file-state-tests", Guid.NewGuid().ToString("N"));
    var bundleRoot = Path.Combine(root, "bundle");
    var workspace = Path.Combine(root, "workspace");
    Directory.CreateDirectory(bundleRoot);
    Directory.CreateDirectory(workspace);

    try
    {
        File.WriteAllText(Path.Combine(bundleRoot, "sample.bam"), "root");
        File.WriteAllText(Path.Combine(workspace, "sample.bam"), "workspace");
        var context = new RenderContext
        {
            BundleRootPath = bundleRoot,
            BundleWorkspacePath = workspace,
            FieldValues = new Dictionary<string, string> { ["alignment"] = "sample.bam" },
        };

        Equal("9", RenderingEngine.Interpolate("{{alignment.fileSize}}", context));
        Equal(workspace, RenderingEngine.Interpolate("{{alignment.parentDir}}", context));
    }
    finally
    {
        if (Directory.Exists(root))
        {
            Directory.Delete(root, recursive: true);
        }
    }
}

static async Task RunsSimpleRedirectedProcess()
{
    var result = await new SimpleProcessRunner().RunAsync(new ProcessExecutionRequest
    {
        Command = new RenderedCommand("cmd.exe", ["/d", "/c", "echo", "gui-for-cli"]),
        Timeout = TimeSpan.FromSeconds(10),
    });

    Equal(0, result.ExitCode);
    Equal(false, result.TimedOut);
    Equal("gui-for-cli", result.StandardOutput.Trim());
}

static string FindRepoRoot()
{
    var directory = new DirectoryInfo(AppContext.BaseDirectory);
    while (directory is not null)
    {
        if (File.Exists(Path.Combine(directory.FullName, "platform", "apple", "Package.swift"))
            && Directory.Exists(Path.Combine(directory.FullName, "examples", "WGSExtract")))
        {
            return directory.FullName;
        }

        directory = directory.Parent;
    }

    throw new InvalidOperationException("Could not find repository root.");
}

static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"Expected {expected}, got {actual}");
    }
}

static void SequenceEqual<T>(IEnumerable<T> expected, IEnumerable<T> actual)
{
    var expectedList = expected.ToList();
    var actualList = actual.ToList();
    if (!expectedList.SequenceEqual(actualList))
    {
        throw new InvalidOperationException($"Expected [{string.Join(", ", expectedList)}], got [{string.Join(", ", actualList)}]");
    }
}
