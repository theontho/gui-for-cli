using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Services;

public static class IconText
{
    private static readonly IReadOnlyDictionary<string, string> Icons = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["app"] = "▣",
        ["checkmark"] = "✓",
        ["checkmark.circle.fill"] = "✓",
        ["checklist"] = "☑",
        ["doc"] = "📄",
        ["doc.text"] = "📄",
        ["folder"] = "📁",
        ["folder.badge.gearshape"] = "🗂",
        ["gearshape"] = "⚙",
        ["gear"] = "⚙",
        ["globe"] = "🌐",
        ["hammer"] = "🔨",
        ["info"] = "ⓘ",
        ["list.bullet"] = "☷",
        ["play"] = "▶",
        ["server.rack"] = "▤",
        ["tablecells"] = "▦",
        ["terminal"] = "▰",
        ["trash"] = "🗑",
        ["tree"] = "🌳",
        ["wrench"] = "🔧",
    };

    public static string For(BundleManifest manifest) =>
        !string.IsNullOrWhiteSpace(manifest.TextIcon) ? manifest.TextIcon! : For(manifest.IconName);

    public static string For(BundlePage page) =>
        !string.IsNullOrWhiteSpace(page.TextIcon) ? page.TextIcon! : For(page.IconName);

    public static string For(PageSection section) =>
        !string.IsNullOrWhiteSpace(section.TextIcon) ? section.TextIcon! : For(section.IconName);

    private static string For(string? iconName) =>
        !string.IsNullOrWhiteSpace(iconName) && Icons.TryGetValue(iconName, out var icon) ? icon : "•";
}
