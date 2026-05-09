using GUIForCLIWindows.Core;

internal static partial class WindowsCoreTests
{
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
    var bundleRoot = Path.Combine(repoRoot, "Examples", "WGSExtract");
    var manifest = ManifestLoader.LoadManifestFromRoot(bundleRoot);
    Equal("wgs-extract", manifest.Id);
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
                                        Options = [new ControlOption { Title = "option.title" }],
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
    Equal("Confirm", control.RowActions[0].Confirm!.Title);
    Equal("Are you sure?", control.RowActions[0].Confirm!.Message);
    Equal("Run", control.RowActions[0].Confirm!.ConfirmButtonTitle);
    Equal("Cancel", control.RowActions[0].Confirm!.CancelButtonTitle);
    Equal("Type value", control.RowActions[0].Confirm!.Prompt);
}

}
