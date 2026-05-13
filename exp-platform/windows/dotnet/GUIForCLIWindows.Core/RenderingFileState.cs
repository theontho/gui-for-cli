using System.Globalization;

namespace GUIForCLIWindows.Core;

public static partial class RenderingEngine
{
    private static string? ComputedFileStateValue(RenderContext context, string placeholder)
    {
        var separator = placeholder.LastIndexOf('.');
        if (separator <= 0 || separator >= placeholder.Length - 1)
        {
            return null;
        }

        if (ValueOrNull(context.FileStateValues, placeholder) is { } serverComputed)
        {
            return serverComputed;
        }

        var fieldID = placeholder[..separator];
        var property = placeholder[(separator + 1)..];
        var rawPath = ValueOrNull(context.FieldValues, fieldID) ?? ValueOrNull(context.ConfigValues, fieldID);

        return property switch
        {
            "pathExtension" => PathExtension(rawPath),
            "parentDir" => ParentDirectory(rawPath, context.BundleRootPath, context.BundleWorkspacePath),
            "exists" => File.Exists(ResolveUserPath(rawPath, context.BundleRootPath, context.BundleWorkspacePath)).ToString().ToLowerInvariant(),
            "fileSize" => FileSize(rawPath, context.BundleRootPath, context.BundleWorkspacePath)?.ToString(CultureInfo.InvariantCulture) ?? "",
            "fileSizeGB" => FileSize(rawPath, context.BundleRootPath, context.BundleWorkspacePath) is { } bytes
                ? (bytes / 1_073_741_824.0).ToString("0.00", CultureInfo.InvariantCulture)
                : "",
            "isIndexed" => IsIndexedAlignment(rawPath, context.BundleRootPath, context.BundleWorkspacePath).ToString().ToLowerInvariant(),
            "isSorted" => IsSortedAlignment(rawPath, context.BundleRootPath, context.BundleWorkspacePath).ToString().ToLowerInvariant(),
            _ => null,
        };
    }

    private static string PathExtension(string? path)
    {
        var name = (path ?? "").Split(['/', '\\']).LastOrDefault() ?? "";
        var dot = name.LastIndexOf('.');
        return dot >= 0 ? name[(dot + 1)..].ToLowerInvariant() : "";
    }

    private static string ParentDirectory(string? path, string? bundleRoot, string? bundleWorkspace)
    {
        var resolved = ResolveUserPath(path, bundleRoot, bundleWorkspace);
        return string.IsNullOrWhiteSpace(resolved) ? "" : Path.GetDirectoryName(resolved) ?? "";
    }

    private static long? FileSize(string? path, string? bundleRoot, string? bundleWorkspace)
    {
        var resolved = ResolveUserPath(path, bundleRoot, bundleWorkspace);
        return File.Exists(resolved) ? new FileInfo(resolved).Length : null;
    }

    private static bool IsIndexedAlignment(string? path, string? bundleRoot, string? bundleWorkspace)
    {
        var resolved = ResolveUserPath(path, bundleRoot, bundleWorkspace);
        if (string.IsNullOrWhiteSpace(resolved))
        {
            return false;
        }

        var directory = Path.GetDirectoryName(resolved) ?? "";
        var withoutExtension = Path.Combine(directory, Path.GetFileNameWithoutExtension(resolved));
        return new[]
        {
            $"{resolved}.bai",
            $"{resolved}.crai",
            $"{resolved}.csi",
            $"{withoutExtension}.bai",
            $"{withoutExtension}.crai",
            $"{withoutExtension}.csi",
        }.Any(File.Exists);
    }

    private static bool IsSortedAlignment(string? path, string? bundleRoot, string? bundleWorkspace)
    {
        var resolved = ResolveUserPath(path, bundleRoot, bundleWorkspace);
        if (IsIndexedAlignment(path, bundleRoot, bundleWorkspace))
        {
            return true;
        }

        var name = Path.GetFileName(resolved).ToLowerInvariant();
        return name.Contains(".sorted.", StringComparison.Ordinal)
            || name.Contains("_sorted.", StringComparison.Ordinal)
            || name.EndsWith(".sorted.bam", StringComparison.Ordinal)
            || name.EndsWith(".sorted.cram", StringComparison.Ordinal)
            || name.Contains(".sort.", StringComparison.Ordinal)
            || name.Contains("_sort.", StringComparison.Ordinal);
    }

    private static string ResolveUserPath(string? path, string? bundleRoot, string? bundleWorkspace)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return "";
        }

        var expanded = path
            .Replace("{{bundleRoot}}", bundleRoot ?? "", StringComparison.Ordinal)
            .Replace("{{bundleWorkspace}}", bundleWorkspace ?? bundleRoot ?? "", StringComparison.Ordinal)
            .Replace("{{home}}", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), StringComparison.Ordinal);
        return Path.IsPathRooted(expanded) || string.IsNullOrWhiteSpace(bundleRoot)
            ? expanded
            : Path.GetFullPath(Path.Combine(bundleRoot, expanded));
    }

}
