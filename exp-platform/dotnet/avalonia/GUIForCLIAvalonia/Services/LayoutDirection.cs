using System.Globalization;
using Avalonia;
using Avalonia.Layout;
using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Services;

public static class LayoutDirection
{
    private static readonly HashSet<string> RtlLanguages = new(StringComparer.OrdinalIgnoreCase)
    {
        "ar", "arc", "dv", "fa", "he", "ku", "ps", "ur", "yi",
    };

    public static FlowDirection InterfaceDirection(BundleState state) =>
        IsRtlLocale(state.LocalizationCode ?? CultureInfo.CurrentUICulture.Name) ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;

    public static FlowDirection TerminalDirection(BundleManifest manifest) =>
        string.Equals(manifest.TerminalTextDirection, "rtl", StringComparison.OrdinalIgnoreCase) ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;

    public static bool IsRtlLocale(string? locale)
    {
        var language = (locale ?? "").Split(['-', '_'], StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
        return RtlLanguages.Contains(language);
    }
}
