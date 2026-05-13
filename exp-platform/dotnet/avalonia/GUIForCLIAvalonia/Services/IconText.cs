using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Services;

public static class IconText
{
    private const string FallbackIcon = "•";

    public static string For(BundleManifest manifest, BundleIconMap iconMap) =>
        !string.IsNullOrWhiteSpace(manifest.TextIcon) ? manifest.TextIcon! : For(manifest.IconName, iconMap);

    public static string For(BundlePage page, BundleIconMap iconMap) =>
        !string.IsNullOrWhiteSpace(page.TextIcon) ? page.TextIcon! : For(page.IconName, iconMap);

    public static string For(PageSection section, BundleIconMap iconMap) =>
        !string.IsNullOrWhiteSpace(section.TextIcon) ? section.TextIcon! : For(section.IconName, iconMap);

    private static string For(string? iconName, BundleIconMap iconMap)
    {
        var icon = iconMap.Resolve(BundleIconMap.EmojiSource, iconName);
        return string.IsNullOrWhiteSpace(icon) ? FallbackIcon : icon;
    }
}
