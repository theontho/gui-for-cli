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
                case "--repo-root" when index + 1 < args.Count:
                    repoRoot = args[++index];
                    break;
                case "--bundle" when index + 1 < args.Count:
                    bundleRoot = args[++index];
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
}
