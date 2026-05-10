using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace GUIForCLIWindows.Core;

public static partial class ManifestLoader
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = false,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

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

        var manifest = manifestObject.Deserialize<BundleManifest>(JsonOptions)
            ?? throw new InvalidOperationException($"Invalid manifest JSON: {manifestPath}");
        return manifest with { PageFiles = pageFiles };
    }

    public static Dictionary<string, string> LoadStringTable(
        string repoRoot,
        string bundleRoot,
        BundleManifest manifest,
        string locale)
    {
        var defaultCode = string.IsNullOrWhiteSpace(manifest.DefaultLocalizationCode) ? "en" : manifest.DefaultLocalizationCode;
        return LocalizationEngine.MergeTables(
            ReadOptionalTable(Path.Combine(repoRoot, "Resources", "BuiltinStrings", "strings.en.toml")),
            locale == "en" ? null : ReadOptionalTable(Path.Combine(repoRoot, "Resources", "BuiltinStrings", $"strings.{locale}.toml")),
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
            return item with { Values = values.ToDictionary(pair => pair.Key, pair => Localized(pair.Value, table)) };
        }

        return item with
        {
            ExtraValues = item.ExtraValues.ToDictionary(
                pair => pair.Key,
                pair => pair.Value.ValueKind == JsonValueKind.String
                    ? JsonSerializer.SerializeToElement(Localized(pair.Value.GetString() ?? "", table))
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
