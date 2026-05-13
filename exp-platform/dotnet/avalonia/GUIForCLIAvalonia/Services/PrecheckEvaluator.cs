using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Services;

public static class PrecheckEvaluator
{
    public static string? Describe(ActionPrecheckSpec? precheck, RenderContext context)
    {
        if (precheck?.DiskSpaceGB is null)
        {
            return null;
        }

        var interpolated = RenderingEngine.Interpolate(precheck.DiskSpaceGB, context);
        var requiredGB = RenderingEngine.EvaluateNumeric(interpolated);
        if (!double.IsFinite(requiredGB) || requiredGB <= 0)
        {
            return null;
        }

        var pathExpression = string.IsNullOrWhiteSpace(precheck.DiskSpacePath) ? "{{out_dir}}" : precheck.DiskSpacePath;
        var targetPath = RenderingEngine.Interpolate(pathExpression, context);
        if (string.IsNullOrWhiteSpace(targetPath))
        {
            targetPath = context.BundleWorkspacePath ?? context.BundleRootPath ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }

        var availableGB = AvailableGB(targetPath);
        if (!double.IsFinite(availableGB))
        {
            return $"Disk space estimate: need about {requiredGB:0.##} GB at {targetPath}.";
        }

        var severity = availableGB < requiredGB ? "warning" : "info";
        return $"Disk space {severity}: need about {requiredGB:0.##} GB at {targetPath}; {availableGB:0.##} GB available.";
    }

    private static double AvailableGB(string rawPath)
    {
        if (!TryFullPath(rawPath, out var path))
        {
            return double.NaN;
        }

        while (!Directory.Exists(path) && !string.IsNullOrWhiteSpace(path))
        {
            var parent = Path.GetDirectoryName(path);
            if (string.Equals(parent, path, StringComparison.Ordinal) || parent is null)
            {
                return double.NaN;
            }

            path = parent;
        }

        var drive = DriveInfo.GetDrives().Where(item => item.IsReady)
            .OrderByDescending(item => path.StartsWith(item.RootDirectory.FullName, StringComparison.OrdinalIgnoreCase) ? item.RootDirectory.FullName.Length : -1)
            .FirstOrDefault();
        return drive is null ? double.NaN : drive.AvailableFreeSpace / 1_073_741_824.0;
    }

    private static bool TryFullPath(string rawPath, out string path)
    {
        try
        {
            path = Path.GetFullPath(Environment.ExpandEnvironmentVariables(rawPath));
            return true;
        }
        catch (Exception error) when (error is ArgumentException
            or IOException
            or NotSupportedException
            or PathTooLongException
            or UnauthorizedAccessException)
        {
            path = "";
            return false;
        }
    }
}
