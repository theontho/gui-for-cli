namespace GUIForCLIAvalonia.Services;

public static class RepoLocator
{
    public static string ResolveRepoRoot(string? requestedRoot)
    {
        if (!string.IsNullOrWhiteSpace(requestedRoot))
        {
            return Path.GetFullPath(requestedRoot);
        }

        foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
        {
            var directory = new DirectoryInfo(start);
            while (directory is not null)
            {
                if (Directory.Exists(Path.Combine(directory.FullName, "resources", "BuiltinStrings"))
                    && Directory.Exists(Path.Combine(directory.FullName, "resources", "BuiltinIconMap"))
                    && Directory.Exists(Path.Combine(directory.FullName, "examples", "WGSExtract")))
                {
                    return directory.FullName;
                }

                directory = directory.Parent;
            }
        }

        throw new InvalidOperationException("Could not find repository root. Pass --repo-root or GFC_REPO_ROOT.");
    }

    public static string ResolveBundleRoot(string repoRoot, string? requestedBundle)
    {
        var bundle = string.IsNullOrWhiteSpace(requestedBundle)
            ? Path.Combine(repoRoot, "examples", "WGSExtract")
            : requestedBundle;
        return Path.GetFullPath(Path.IsPathRooted(bundle) ? bundle : Path.Combine(repoRoot, bundle));
    }
}
