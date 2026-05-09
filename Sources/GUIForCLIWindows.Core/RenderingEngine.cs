using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace GUIForCLIWindows.Core;

public static partial class RenderingEngine
{
    public static IReadOnlyList<ControlSpec> AllControls(BundleManifest manifest) =>
        manifest.Pages.SelectMany(page => page.Sections).SelectMany(section => section.Controls).ToList();

    public static IReadOnlyList<ControlSpec> ConfigEditorControls(BundleManifest manifest) =>
        AllControls(manifest).Where(control => control.Kind == "configEditor").ToList();

    public static string ConfigValueKey(ControlSpec control, ConfigSettingSpec setting) => $"{control.Id}.{setting.Id}";

    public static bool PersistsFieldValue(string kind) => kind is "text" or "path" or "dropdown" or "toggle";

    public static Dictionary<string, string> InitialFieldValues(BundleManifest manifest)
    {
        var values = new Dictionary<string, string>();
        foreach (var control in AllControls(manifest).Where(control => PersistsFieldValue(control.Kind)))
        {
            if (!values.ContainsKey(control.Id) || control.Value is not null)
            {
                values[control.Id] = control.Value ?? "";
            }
        }

        return values;
    }

    public static Dictionary<string, IReadOnlySet<string>> InitialCheckedOptions(BundleManifest manifest) =>
        AllControls(manifest)
            .Where(control => control.Kind == "checkboxGroup")
            .ToDictionary(
                control => control.Id,
                control => (IReadOnlySet<string>)control.Options
                    .Where(option => option.Selected)
                    .Select(option => option.Id)
                    .ToHashSet(StringComparer.Ordinal));

    public static Dictionary<string, string> InitialConfigValues(BundleManifest manifest)
    {
        var values = new Dictionary<string, string>();
        foreach (var control in ConfigEditorControls(manifest))
        {
            foreach (var setting in control.Settings)
            {
                values[ConfigValueKey(control, setting)] = setting.Value ?? "";
            }
        }

        return values;
    }

    public static Dictionary<string, string> CheckedOptionsForContext(IReadOnlyDictionary<string, IReadOnlyCollection<string>> checkedOptions) =>
        checkedOptions.ToDictionary(
            pair => pair.Key,
            pair => string.Join(",", pair.Value.Order(StringComparer.Ordinal)),
            StringComparer.Ordinal);

}
