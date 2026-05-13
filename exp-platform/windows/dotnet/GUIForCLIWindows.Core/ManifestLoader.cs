using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace GUIForCLIWindows.Core;

public static partial class ManifestLoader
{
    public static BundleManifest LoadManifestFromRoot(string bundleRoot)
    {
        var manifestPath = Path.Combine(bundleRoot, "manifest.json");
        var manifestObject = JsonNode.Parse(File.ReadAllText(manifestPath))?.AsObject()
            ?? throw new InvalidOperationException($"Invalid manifest JSON: {manifestPath}");

        var pageFiles = new List<string>();
        if (manifestObject["pages"] is JsonArray pagesArray && pagesArray.All(page => page is JsonValue value && value.TryGetValue<string>(out _)))
        {
            var loadedPages = new JsonArray();
            foreach (var pageNode in pagesArray)
            {
                var pageFile = pageNode!.GetValue<string>();
                if (!IsSafePageFileName(pageFile))
                {
                    throw new InvalidOperationException($"Invalid page file name: {pageFile}");
                }

                pageFiles.Add(pageFile);
                loadedPages.Add(JsonNode.Parse(File.ReadAllText(Path.Combine(bundleRoot, "pages", pageFile))));
            }

            manifestObject["pages"] = loadedPages;
        }

        var manifest = manifestObject.Deserialize(CoreJsonContext.Default.BundleManifest)
            ?? throw new InvalidOperationException($"Invalid manifest JSON: {manifestPath}");
        return NormalizeManifest(manifest with { PageFiles = pageFiles });
    }

    public static Dictionary<string, string> LoadStringTable(
        string repoRoot,
        string bundleRoot,
        BundleManifest manifest,
        string locale)
    {
        var defaultCode = string.IsNullOrWhiteSpace(manifest.DefaultLocalizationCode) ? "en" : manifest.DefaultLocalizationCode;
        var builtinStringsRoot = Path.Combine(repoRoot, "platform", "apple", "shared", "Sources", "GUIForCLICore", "Resources", "BuiltinStrings");
        return LocalizationEngine.MergeTables(
            ReadOptionalTable(Path.Combine(builtinStringsRoot, "strings.en.toml")),
            locale == "en" ? null : ReadOptionalTable(Path.Combine(builtinStringsRoot, $"strings.{locale}.toml")),
            ReadOptionalTable(Path.Combine(bundleRoot, "strings", $"strings.{defaultCode}.toml")),
            locale == defaultCode ? null : ReadOptionalTable(Path.Combine(bundleRoot, "strings", $"strings.{locale}.toml")));
    }

    public static BundleManifest LocalizeManifest(BundleManifest manifest, IReadOnlyDictionary<string, string> table) =>
        manifest with
        {
            DisplayName = Localized(manifest.DisplayName, table),
            Summary = Localized(manifest.Summary, table),
            Setup = manifest.Setup with { Steps = manifest.Setup.Steps.Select(step => step with { Label = Localized(step.Label, table) }).ToList() },
            ExitCodeReference = manifest.ExitCodeReference.Select(entry => entry with
            {
                Title = Localized(entry.Title, table),
                Summary = Localized(entry.Summary, table),
            }).ToList(),
            Pages = manifest.Pages.Select(page => LocalizePage(page, table)).ToList(),
        };

    private static BundleManifest NormalizeManifest(BundleManifest manifest) =>
        manifest with
        {
            Id = manifest.Id ?? "",
            DisplayName = manifest.DisplayName ?? "",
            Summary = manifest.Summary ?? "",
            TerminalTextDirection = NormalizeTextDirection(manifest.TerminalTextDirection),
            DefaultLocalizationCode = string.IsNullOrWhiteSpace(manifest.DefaultLocalizationCode) ? "en" : manifest.DefaultLocalizationCode,
            Pages = (manifest.Pages ?? []).Select(NormalizePage).ToList(),
            Setup = NormalizeSetup(manifest.Setup ?? new SetupSpec()),
            ExitCodeReference = (manifest.ExitCodeReference ?? []).Select(NormalizeExitCodeReference).ToList(),
            PageFiles = manifest.PageFiles ?? [],
        };

    private static BundlePage NormalizePage(BundlePage page) =>
        page with
        {
            Id = page.Id ?? "",
            Title = page.Title ?? "",
            Summary = page.Summary ?? "",
            Sections = (page.Sections ?? []).Select(NormalizeSection).ToList(),
        };

    private static PageSection NormalizeSection(PageSection section) =>
        section with
        {
            Id = section.Id ?? "",
            Summary = section.Summary ?? section.Subtitle,
            DataSource = section.DataSource is null ? null : NormalizeDataSource(section.DataSource),
            Controls = (section.Controls ?? []).Select(NormalizeControl).ToList(),
            Actions = (section.Actions ?? []).Select(NormalizeAction).ToList(),
        };

    private static ControlSpec NormalizeControl(ControlSpec control) =>
        control with
        {
            Id = control.Id ?? "",
            Label = control.Label ?? "",
            Kind = control.Kind ?? "",
            Options = (control.Options ?? []).Select(NormalizeControlOption).ToList(),
            Columns = (control.Columns ?? []).Select(column => column with { Id = column.Id ?? "", Title = column.Title ?? "" }).ToList(),
            Rows = (control.Rows ?? []).Select(NormalizeRow).ToList(),
            RowTemplate = control.RowTemplate is null ? null : NormalizeRow(control.RowTemplate),
            Items = (control.Items ?? []).Select(NormalizeItem).ToList(),
            RowActions = (control.RowActions ?? []).Select(NormalizeAction).ToList(),
            Settings = (control.Settings ?? []).Select(NormalizeSetting).ToList(),
            ConfigFile = control.ConfigFile is null ? null : control.ConfigFile with { Path = control.ConfigFile.Path ?? "" },
            DataSource = control.DataSource is null ? null : NormalizeDataSource(control.DataSource),
        };

    private static ControlOption NormalizeControlOption(ControlOption option) =>
        option with
        {
            Id = option.Id ?? "",
            Title = option.Title ?? "",
        };

    private static ListRowSpec NormalizeRow(ListRowSpec row) =>
        row with
        {
            Values = row.Values ?? [],
            Tags = (row.Tags ?? []).Select(tag => tag with { Id = tag.Id ?? "", Title = tag.Title ?? "" }).ToList(),
        };

    private static ListItemSpec NormalizeItem(ListItemSpec item) =>
        new()
        {
            Values = item.Values,
            ExtraValues = item.ExtraValues ?? [],
        };

    private static ConfigSettingSpec NormalizeSetting(ConfigSettingSpec setting) =>
        setting with
        {
            Id = setting.Id ?? "",
            Kind = setting.Kind ?? "",
            Key = setting.Key ?? "",
            Label = setting.Label ?? "",
            Options = (setting.Options ?? []).Select(NormalizeControlOption).ToList(),
            DataSource = setting.DataSource is null ? null : NormalizeDataSource(setting.DataSource),
        };

    private static ActionSpec NormalizeAction(ActionSpec action) =>
        action with
        {
            Id = action.Id ?? "",
            Title = action.Title ?? "",
            Role = action.Role,
            Destructive = action.Destructive || string.Equals(action.Role, "destructive", StringComparison.OrdinalIgnoreCase),
            VisibleWhen = (action.VisibleWhen ?? []).Select(NormalizeCondition).ToList(),
            DisabledWhen = (action.DisabledWhen ?? []).Select(NormalizeCondition).ToList(),
            Command = NormalizeCommand(action.Command ?? new CommandSpec()),
            Confirm = action.Confirm is null ? null : action.Confirm with
            {
                Title = action.Confirm.Title ?? "",
                Message = action.Confirm.Message ?? "",
                ConfirmButtonTitle = action.Confirm.ConfirmButtonTitle ?? "",
                CancelButtonTitle = action.Confirm.CancelButtonTitle ?? "",
            },
            Precheck = action.Precheck,
        };

    private static ActionConditionSpec NormalizeCondition(ActionConditionSpec condition) =>
        condition with
        {
            Placeholder = condition.Placeholder ?? "",
            In = condition.In ?? [],
            NotIn = condition.NotIn ?? [],
        };

    private static CommandSpec NormalizeCommand(CommandSpec command) =>
        command with
        {
            Executable = command.Executable ?? "",
            Arguments = command.Arguments ?? [],
            OptionalArguments = command.OptionalArguments ?? [],
        };

    private static DataSourceSpec NormalizeDataSource(DataSourceSpec dataSource) =>
        dataSource with
        {
            Path = dataSource.Path ?? "",
            Arguments = dataSource.Arguments ?? [],
            Environment = dataSource.Environment ?? [],
        };

    private static string NormalizeTextDirection(string? value)
    {
        var normalized = (value ?? "").Trim().ToLowerInvariant();
        return normalized is "rtl" or "right-to-left" or "righttoleft" ? "rtl" : "ltr";
    }

    private static SetupSpec NormalizeSetup(SetupSpec setup) =>
        setup with
        {
            Steps = (setup.Steps ?? []).Select(step => step with
            {
                Id = step.Id ?? "",
                Label = step.Label ?? "",
                Kind = step.Kind ?? "",
                Command = step.Command is null ? null : NormalizeCommand(step.Command),
                Arguments = step.Arguments ?? [],
                Environment = step.Environment ?? [],
            }).ToList(),
        };

    private static ExitCodeReferenceSpec NormalizeExitCodeReference(ExitCodeReferenceSpec entry) =>
        entry with
        {
            Title = entry.Title ?? "",
            Summary = entry.Summary ?? "",
            Severity = string.IsNullOrWhiteSpace(entry.Severity) ? "error" : entry.Severity,
        };

    private static BundlePage LocalizePage(BundlePage page, IReadOnlyDictionary<string, string> table) =>
        page with
        {
            Title = Localized(page.Title, table),
            Summary = Localized(page.Summary, table),
            SidebarGroup = LocalizedOptional(page.SidebarGroup, table),
            Sections = page.Sections.Select(section => LocalizeSection(section, table)).ToList(),
        };

    private static PageSection LocalizeSection(PageSection section, IReadOnlyDictionary<string, string> table) =>
        section with
        {
            Title = LocalizedOptional(section.Title, table),
            Subtitle = LocalizedOptional(section.Subtitle, table),
            Summary = LocalizedOptional(section.Summary, table),
            Controls = section.Controls.Select(control => LocalizeControl(control, table)).ToList(),
            Actions = section.Actions.Select(action => LocalizeAction(action, table)).ToList(),
        };

    private static ControlSpec LocalizeControl(ControlSpec control, IReadOnlyDictionary<string, string> table) =>
        control with
        {
            Label = Localized(control.Label, table),
            Placeholder = LocalizedOptional(control.Placeholder, table),
            Tooltip = LocalizedOptional(control.Tooltip, table),
            Options = control.Options.Select(option => option with
            {
                Title = Localized(option.Title, table),
                Group = LocalizedOptional(option.Group, table),
            }).ToList(),
            Columns = control.Columns.Select(column => column with { Title = Localized(column.Title, table) }).ToList(),
            Rows = control.Rows.Select(row => LocalizeRow(row, table)).ToList(),
            Items = control.Items.Select(item => LocalizeItem(item, table)).ToList(),
            RowTemplate = control.RowTemplate is null ? null : LocalizeRow(control.RowTemplate, table),
            RowActions = control.RowActions.Select(action => LocalizeAction(action, table)).ToList(),
            Settings = control.Settings.Select(setting => LocalizeSetting(setting, table)).ToList(),
        };

    private static ListItemSpec LocalizeItem(ListItemSpec item, IReadOnlyDictionary<string, string> table)
    {
        if (item.Values is { } values)
        {
            return new ListItemSpec
            {
                Values = values.ToDictionary(pair => pair.Key, pair => Localized(pair.Value, table)),
                ExtraValues = item.ExtraValues.ToDictionary(pair => pair.Key, pair => pair.Value),
            };
        }

        return new ListItemSpec
        {
            ExtraValues = item.ExtraValues.ToDictionary(
                pair => pair.Key,
                pair => pair.Value.ValueKind == JsonValueKind.String
                    ? JsonSerializer.SerializeToElement(Localized(pair.Value.GetString() ?? "", table), CoreJsonContext.Default.String)
                    : pair.Value),
        };
    }

    private static ListRowSpec LocalizeRow(ListRowSpec row, IReadOnlyDictionary<string, string> table) =>
        row with
        {
            Title = LocalizedOptional(row.Title, table),
            Status = LocalizedOptional(row.Status, table),
            Tags = row.Tags.Select(tag => tag with { Title = Localized(tag.Title, table) }).ToList(),
            Tooltip = LocalizedOptional(row.Tooltip, table),
        };

    private static ActionSpec LocalizeAction(ActionSpec action, IReadOnlyDictionary<string, string> table) =>
        action with
        {
            Title = Localized(action.Title, table),
            Tooltip = LocalizedOptional(action.Tooltip, table),
            DisabledTooltip = LocalizedOptional(action.DisabledTooltip, table),
            Confirm = action.Confirm is null ? null : LocalizeConfirmation(action.Confirm, table),
        };

    private static ConfirmationSpec LocalizeConfirmation(ConfirmationSpec confirm, IReadOnlyDictionary<string, string> table) =>
        confirm with
        {
            Title = Localized(confirm.Title, table),
            Message = Localized(confirm.Message, table),
            ConfirmButtonTitle = Localized(confirm.ConfirmButtonTitle, table),
            CancelButtonTitle = Localized(confirm.CancelButtonTitle, table),
            RequiredText = LocalizedOptional(confirm.RequiredText, table),
            Prompt = LocalizedOptional(confirm.Prompt, table),
        };

    private static ConfigSettingSpec LocalizeSetting(ConfigSettingSpec setting, IReadOnlyDictionary<string, string> table) =>
        setting with
        {
            Label = Localized(setting.Label, table),
            Placeholder = LocalizedOptional(setting.Placeholder, table),
            Tooltip = LocalizedOptional(setting.Tooltip, table),
            Options = setting.Options.Select(option => option with
            {
                Title = Localized(option.Title, table),
                Group = LocalizedOptional(option.Group, table),
            }).ToList(),
        };

    private static Dictionary<string, string> ReadOptionalTable(string path)
    {
        return File.Exists(path)
            ? LocalizationEngine.ParseTomlStrings(File.ReadAllText(path))
            : [];
    }

    private static bool IsSafePageFileName(string fileName) =>
        PageFileNameRegex().IsMatch(fileName) && !fileName.Contains('/') && !fileName.Contains('\\');

    private static string Localized(string value, IReadOnlyDictionary<string, string> table) =>
        table.TryGetValue(value, out var localized) ? localized : value;

    private static string? LocalizedOptional(string? value, IReadOnlyDictionary<string, string> table) =>
        value is null ? null : Localized(value, table);

    [GeneratedRegex(@"^[A-Za-z0-9._-]+\.json$")]
    private static partial Regex PageFileNameRegex();
}
