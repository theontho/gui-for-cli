using Avalonia.Controls;
using Avalonia.Platform.Storage;

namespace GUIForCLIAvalonia.Views;

public static class PathPickerService
{
    public static async Task<string?> PickAsync(TopLevel owner, string label, string currentPath, bool folder)
    {
        var suggested = await SuggestedFolderAsync(owner, currentPath);
        if (folder)
        {
            var folders = await owner.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
            {
                Title = $"Choose {label}",
                AllowMultiple = false,
                SuggestedStartLocation = suggested,
            });
            return folders.FirstOrDefault()?.Path.LocalPath;
        }

        var files = await owner.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = $"Choose {label}",
            AllowMultiple = false,
            SuggestedStartLocation = suggested,
        });
        return files.FirstOrDefault()?.Path.LocalPath;
    }

    public static bool LooksLikeFolder(string id, string label, string? placeholder, string? tooltip)
    {
        var text = $"{id} {label} {placeholder} {tooltip}".ToLowerInvariant();
        return text.Contains("directory", StringComparison.Ordinal)
            || text.Contains("folder", StringComparison.Ordinal)
            || text.Contains("library", StringComparison.Ordinal)
            || text.Contains("reference", StringComparison.Ordinal)
            || text.Contains("cache", StringComparison.Ordinal)
            || text.Contains("out_dir", StringComparison.Ordinal)
            || text.Contains("output_dir", StringComparison.Ordinal)
            || text.EndsWith("_dir", StringComparison.Ordinal);
    }

    private static async Task<IStorageFolder?> SuggestedFolderAsync(TopLevel owner, string currentPath)
    {
        var candidate = SuggestedPath(currentPath);
        if (candidate is null)
        {
            return null;
        }

        try
        {
            return await owner.StorageProvider.TryGetFolderFromPathAsync(new Uri(candidate));
        }
        catch
        {
            return null;
        }
    }

    private static string? SuggestedPath(string currentPath)
    {
        if (string.IsNullOrWhiteSpace(currentPath))
        {
            return null;
        }

        var expanded = Environment.ExpandEnvironmentVariables(currentPath);
        if (Directory.Exists(expanded))
        {
            return expanded;
        }

        if (File.Exists(expanded))
        {
            return Path.GetDirectoryName(expanded);
        }

        var parent = Path.GetDirectoryName(expanded);
        return !string.IsNullOrWhiteSpace(parent) && Directory.Exists(parent) ? parent : null;
    }
}
