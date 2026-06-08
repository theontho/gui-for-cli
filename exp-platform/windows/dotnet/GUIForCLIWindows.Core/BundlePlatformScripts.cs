namespace GUIForCLIWindows.Core;

public static class BundlePlatformScripts
{
    private static readonly string[] WindowsExtensions = [".ps1", ".cmd", ".bat", ".py"];

    public static void ValidateCompleteSets(BundleManifest manifest, string bundleRoot)
    {
        var allRequired = ReferencedScriptStems(manifest).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (allRequired.Count == 0)
        {
            return;
        }

        var scriptsRoot = Path.Combine(bundleRoot, "scripts");
        var folders = PlatformScriptFolders(scriptsRoot).ToList();
        if (folders.Count == 0)
        {
            return;
        }
        var shared = ScriptStemsInDirectory(scriptsRoot);
        foreach (var folder in folders)
        {
            var required = ReferencedScriptStems(manifest, PlatformsForScriptFolder(folder, scriptsRoot))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (required.Count == 0)
            {
                continue;
            }
            var present = shared.Concat(ScriptStemsInDirectory(folder))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var missing = required.Where(stem => !present.Contains(stem)).OrderBy(stem => stem, StringComparer.OrdinalIgnoreCase).ToList();
            if (missing.Count > 0)
            {
                throw new InvalidOperationException(
                    $"Platform script folder {Path.GetRelativePath(bundleRoot, folder)} is missing required scripts: {string.Join(", ", missing)}");
            }
        }
    }

    private static IEnumerable<string> ScriptStemsInDirectory(string folder)
    {
        return Directory.EnumerateFiles(folder).Select(file => Path.GetFileNameWithoutExtension(file)!);
    }

    public static string ResolveWindowsScript(string executable)
    {
        if (!OperatingSystem.IsWindows() || Path.GetExtension(executable).ToLowerInvariant() != ".sh")
        {
            return executable;
        }

        var directory = Path.GetDirectoryName(executable);
        if (directory is null || !string.Equals(Path.GetFileName(directory), "scripts", StringComparison.OrdinalIgnoreCase))
        {
            return executable;
        }

        var stem = Path.GetFileNameWithoutExtension(executable);
        foreach (var extension in WindowsExtensions)
        {
            var candidate = Path.Combine(directory, "windows", $"{stem}{extension}");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return executable;
    }

    private static IEnumerable<string> ReferencedScriptStems(BundleManifest manifest, IReadOnlyCollection<string>? platforms = null)
    {
        foreach (var step in manifest.Setup.Steps)
        {
            if ((platforms is null || StepAppliesToAnyPlatform(step, platforms))
                && (step.Kind is "setupScript" or "bundledScript")
                && IsScriptPath(step.Value))
            {
                yield return ScriptStem(step.Value);
            }
        }
        foreach (var step in manifest.Uninstall.Steps)
        {
            if ((step.Kind is "setupScript" or "bundledScript") && IsScriptPath(step.Value))
            {
                yield return ScriptStem(step.Value);
            }
        }

        foreach (var page in manifest.Pages)
        {
            foreach (var section in page.Sections)
            {
                if (section.DataSource is not null && IsScriptPath(section.DataSource.Path))
                {
                    yield return ScriptStem(section.DataSource.Path);
                }
                foreach (var action in section.Actions.Concat(section.Controls.SelectMany(control => control.RowActions)))
                {
                    if (IsScriptPath(action.Command.Executable))
                    {
                        yield return ScriptStem(action.Command.Executable);
                    }
                }
                foreach (var control in section.Controls)
                {
                    if (control.DataSource is not null && IsScriptPath(control.DataSource.Path))
                    {
                        yield return ScriptStem(control.DataSource.Path);
                    }
                }
            }
        }
    }

    private static IReadOnlyCollection<string> PlatformsForScriptFolder(string folder, string scriptsRoot)
    {
        var relative = Path.GetRelativePath(scriptsRoot, folder).Replace('\\', '/');
        if (relative.Equals("windows", StringComparison.OrdinalIgnoreCase) || relative.StartsWith("windows/", StringComparison.OrdinalIgnoreCase))
        {
            return ["windows"];
        }
        if (relative.Equals("macos", StringComparison.OrdinalIgnoreCase) || relative.StartsWith("macos/", StringComparison.OrdinalIgnoreCase))
        {
            return ["macos"];
        }
        if (relative.Equals("posix", StringComparison.OrdinalIgnoreCase) || relative.StartsWith("posix/", StringComparison.OrdinalIgnoreCase))
        {
            return ["macos", "linux", "posix"];
        }
        return relative.Equals("linux", StringComparison.OrdinalIgnoreCase) || relative.StartsWith("linux/", StringComparison.OrdinalIgnoreCase)
            ? ["linux"]
            : ["posix"];
    }

    private static bool StepAppliesToAnyPlatform(SetupStepSpec step, IReadOnlyCollection<string> platforms)
    {
        if (step.Platforms is null || step.Platforms.Count == 0)
        {
            return true;
        }
        return step.Platforms
            .Where(platform => !string.IsNullOrWhiteSpace(platform))
            .Select(SetupPlatformAlias)
            .Where(platform => platform is not null)
            .Any(candidate => platforms.Any(platform => SetupPlatformMatches(candidate!, platform)));
    }

    private static string? SetupPlatformAlias(string value)
    {
        return value.Trim().ToLowerInvariant() switch
        {
            "darwin" or "mac" or "macos" => "macos",
            "win" or "win32" or "windows" => "windows",
            "linux" => "linux",
            "posix" => "posix",
            _ => null,
        };
    }

    private static bool SetupPlatformMatches(string candidate, string platform)
    {
        return candidate == "posix" ? platform != "windows" : candidate == platform;
    }

    private static IEnumerable<string> PlatformScriptFolders(string scriptsRoot)
    {
        foreach (var name in new[] { "windows", "posix", "macos" })
        {
            var folder = Path.Combine(scriptsRoot, name);
            if (Directory.Exists(folder))
            {
                yield return folder;
            }
        }

        var linuxRoot = Path.Combine(scriptsRoot, "linux");
        if (!Directory.Exists(linuxRoot))
        {
            yield break;
        }

        if (Directory.EnumerateFiles(linuxRoot).Any())
        {
            yield return linuxRoot;
        }
        foreach (var folder in Directory.EnumerateDirectories(linuxRoot))
        {
            yield return folder;
        }
    }

    private static bool IsScriptPath(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }
        var normalized = Normalize(value);
        return normalized.StartsWith("scripts/", StringComparison.OrdinalIgnoreCase)
            && !normalized.Split('/').Contains("..")
            && !Path.IsPathRooted(normalized);
    }

    private static string ScriptStem(string? value) => Path.GetFileNameWithoutExtension(Normalize(value ?? ""));

    private static string Normalize(string value)
    {
        var normalized = value.Replace('\\', '/');
        if (normalized.StartsWith("{{bundleRoot}}/", StringComparison.OrdinalIgnoreCase))
        {
            normalized = normalized["{{bundleRoot}}/".Length..];
        }
        if (normalized.StartsWith("./", StringComparison.Ordinal))
        {
            normalized = normalized[2..];
        }
        return normalized;
    }
}
