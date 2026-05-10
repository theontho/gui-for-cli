using System.Text.Json;

namespace GUIForCLIWindows.Core;

public sealed class BundleRuntimeService(SimpleProcessRunner processRunner)
{
    private const int DataSourceTimeoutMilliseconds = 15_000;

    public async Task<DataSourcePayload> RunDataSourceAsync(
        DataSourceSpec dataSource,
        RenderContext context,
        string bundleRoot,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(dataSource.Path))
        {
            throw new InvalidOperationException("Missing data source path.");
        }

        var resolvedContext = context with { FileStateValues = await FileStateValuesAsync(context, bundleRoot, cancellationToken).ConfigureAwait(false) };
        var executable = ResolveBundlePath(dataSource.Path, bundleRoot);
        var workingDirectory = dataSource.WorkingDirectory is null
            ? bundleRoot
            : ResolveBundlePath(dataSource.WorkingDirectory, bundleRoot);
        var arguments = dataSource.Arguments.Select(argument => RenderingEngine.Interpolate(argument, resolvedContext)).ToList();
        var environment = new Dictionary<string, string>(dataSource.Environment.ToDictionary(
            pair => pair.Key,
            pair => RenderingEngine.Interpolate(pair.Value, resolvedContext)))
        {
            ["GUI_FOR_CLI_BUNDLE_ROOT"] = bundleRoot,
            ["GUI_FOR_CLI_BUNDLE_WORKSPACE"] = context.BundleRootPath ?? bundleRoot,
            ["GUI_FOR_CLI_DATA_SOURCE"] = "1",
        };

        foreach (var (key, value) in context.FieldValues)
        {
            environment[$"GUI_FOR_CLI_FIELD_{EnvironmentKey(key)}"] = value;
        }

        foreach (var (key, value) in context.ConfigValues)
        {
            environment[$"GUI_FOR_CLI_CONFIG_{EnvironmentKey(key)}"] = value;
        }

        var result = await processRunner.RunAsync(new ProcessExecutionRequest
        {
            Command = new RenderedCommand(executable, arguments),
            WorkingDirectory = workingDirectory,
            Environment = environment,
            Timeout = TimeSpan.FromMilliseconds(DataSourceTimeoutMilliseconds),
        }, cancellationToken).ConfigureAwait(false);

        if (result.ExitCode != 0)
        {
            throw new InvalidOperationException($"Data source {dataSource.Path} exited {result.ExitCode}: {result.StandardError.Trim()}");
        }

        return JsonSerializer.Deserialize<DataSourcePayload>(result.StandardOutput)
            ?? new DataSourcePayload();
    }

    public async Task<Dictionary<string, string>> FileStateValuesAsync(
        RenderContext context,
        string bundleRoot,
        CancellationToken cancellationToken = default)
    {
        var values = new Dictionary<string, string>();
        foreach (var (id, rawPath) in context.FieldValues.Concat(context.ConfigValues).Concat(context.RowValues))
        {
            foreach (var (key, value) in await FileStateForPathAsync(id, rawPath, bundleRoot, cancellationToken).ConfigureAwait(false))
            {
                values[key] = value;
            }
        }

        return values;
    }

    public static string ResolveBundlePath(string value, string bundleRoot)
    {
        var expanded = BundleStateStore.ExpandPathTokens(value, bundleRoot);
        if (Path.IsPathRooted(expanded))
        {
            throw new InvalidOperationException($"Bundle script paths must be relative: {value}");
        }

        var root = Path.GetFullPath(bundleRoot);
        var candidate = Path.GetFullPath(Path.Combine(root, expanded));
        if (!candidate.StartsWith($"{root}{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(candidate, root, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"Bundle script path escapes bundle root: {value}");
        }

        return candidate;
    }

    private static async Task<Dictionary<string, string>> FileStateForPathAsync(
        string id,
        string? rawPath,
        string bundleRoot,
        CancellationToken cancellationToken)
    {
        var values = new Dictionary<string, string>
        {
            [$"{id}.pathExtension"] = "",
            [$"{id}.isIndexed"] = "false",
            [$"{id}.isSorted"] = "false",
            [$"{id}.exists"] = "false",
            [$"{id}.fileSize"] = "",
            [$"{id}.fileSizeGB"] = "",
            [$"{id}.parentDir"] = "",
        };
        if (string.IsNullOrWhiteSpace(rawPath))
        {
            return values;
        }

        var resolvedPath = ResolveUserPath(rawPath, bundleRoot);
        values[$"{id}.pathExtension"] = Path.GetExtension(resolvedPath).TrimStart('.').ToLowerInvariant();
        values[$"{id}.parentDir"] = Path.GetDirectoryName(resolvedPath) ?? "";
        values[$"{id}.isIndexed"] = (await IsIndexedAlignmentAsync(resolvedPath, cancellationToken).ConfigureAwait(false)).ToString().ToLowerInvariant();
        values[$"{id}.isSorted"] = (await IsSortedAlignmentAsync(resolvedPath, cancellationToken).ConfigureAwait(false)).ToString().ToLowerInvariant();

        if (File.Exists(resolvedPath))
        {
            var info = new FileInfo(resolvedPath);
            values[$"{id}.exists"] = "true";
            values[$"{id}.fileSize"] = info.Length.ToString();
            values[$"{id}.fileSizeGB"] = (info.Length / 1_073_741_824.0).ToString("0.00");
        }

        return values;
    }

    private static string ResolveUserPath(string value, string bundleRoot)
    {
        var expanded = BundleStateStore.ExpandPathTokens(value, bundleRoot);
        return Path.IsPathRooted(expanded) ? expanded : Path.GetFullPath(Path.Combine(bundleRoot, expanded));
    }

    private static async Task<bool> IsIndexedAlignmentAsync(string resolvedPath, CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(resolvedPath) ?? "";
        var withoutExtension = Path.Combine(directory, Path.GetFileNameWithoutExtension(resolvedPath));
        var candidates = new[]
        {
            $"{resolvedPath}.bai",
            $"{resolvedPath}.crai",
            $"{resolvedPath}.csi",
            $"{withoutExtension}.bai",
            $"{withoutExtension}.crai",
            $"{withoutExtension}.csi",
        };
        foreach (var candidate in candidates)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (File.Exists(candidate))
            {
                return true;
            }
        }

        await Task.CompletedTask;
        return false;
    }

    private static async Task<bool> IsSortedAlignmentAsync(string resolvedPath, CancellationToken cancellationToken)
    {
        if (await IsIndexedAlignmentAsync(resolvedPath, cancellationToken).ConfigureAwait(false))
        {
            return true;
        }

        var name = Path.GetFileName(resolvedPath).ToLowerInvariant();
        return name.Contains(".sorted.", StringComparison.Ordinal)
            || name.Contains("_sorted.", StringComparison.Ordinal)
            || name.EndsWith(".sorted.bam", StringComparison.Ordinal)
            || name.EndsWith(".sorted.cram", StringComparison.Ordinal)
            || name.Contains(".sort.", StringComparison.Ordinal)
            || name.Contains("_sort.", StringComparison.Ordinal);
    }

    private static string EnvironmentKey(string value) =>
        new(value.Select(character => char.IsAsciiLetterOrDigit(character) ? char.ToUpperInvariant(character) : '_').ToArray());
}
