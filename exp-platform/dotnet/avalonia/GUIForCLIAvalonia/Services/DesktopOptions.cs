using System.Diagnostics;

namespace GUIForCLIAvalonia.Services;

public sealed record DesktopOptions(string? RepoRoot, string? BundleRoot, bool Benchmark, bool Once)
{
    public Stopwatch BootTimer { get; } = Stopwatch.StartNew();

    public static DesktopOptions Parse(IReadOnlyList<string> args)
    {
        string? repoRoot = Environment.GetEnvironmentVariable("GFC_REPO_ROOT");
        string? bundleRoot = Environment.GetEnvironmentVariable("GFC_BUNDLE_ROOT");
        var benchmark = false;
        var once = false;

        for (var index = 0; index < args.Count; index += 1)
        {
            var arg = args[index];
            switch (arg)
            {
                case "--repo-root":
                    repoRoot = RequiredValue(args, ref index, "--repo-root");
                    break;
                case "--bundle":
                    bundleRoot = RequiredValue(args, ref index, "--bundle");
                    break;
                case "--benchmark":
                case "--benchmark-full":
                    benchmark = true;
                    break;
                case "--once":
                    once = true;
                    break;
            }
        }

        return new DesktopOptions(repoRoot, bundleRoot, benchmark, once);
    }

    private static string RequiredValue(IReadOnlyList<string> args, ref int index, string option)
    {
        if (index + 1 >= args.Count)
        {
            throw new ArgumentException($"{option} requires a value.", nameof(args));
        }

        var value = args[index + 1];
        if (string.IsNullOrWhiteSpace(value) || value.StartsWith("--", StringComparison.Ordinal))
        {
            throw new ArgumentException($"{option} requires a value.", nameof(args));
        }

        index += 1;
        return value;
    }
}
