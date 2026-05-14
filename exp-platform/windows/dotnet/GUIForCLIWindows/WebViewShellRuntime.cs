namespace GUIForCLIWindows;

internal sealed record WebViewShellRuntime(
    string RepoRoot,
    string NodeExecutable,
    string ServerScriptPath,
    string BundleRoot,
    string Host,
    int Port,
    bool ExitAfterReady)
{
    public static bool ShouldLaunch(string[] args) =>
        args.Any(argument => string.Equals(argument, "--webview-shell", StringComparison.OrdinalIgnoreCase))
        || IsEnabled(Environment.GetEnvironmentVariable("GFC_WEBVIEW_SHELL"));

    public static WebViewShellRuntime Resolve()
    {
        var host = Environment.GetEnvironmentVariable("GFC_HOST") ?? "127.0.0.1";
        var port = ParsePort(Environment.GetEnvironmentVariable("GFC_PORT"));
        var exitAfterReady = IsEnabled(Environment.GetEnvironmentVariable("GFC_BENCH_EXIT_AFTER_READY"));

        var repoRoot = ResolveRepoRoot();
        var serverScriptPath = Path.Combine(repoRoot, "platform", "typescript", "dist", "web", "src", "server", "main.js");
        if (!File.Exists(serverScriptPath))
        {
            throw new InvalidOperationException($"Missing WebUI server script: {serverScriptPath}");
        }

        var bundleRoot = Environment.GetEnvironmentVariable("GFC_BUNDLE");
        bundleRoot = string.IsNullOrWhiteSpace(bundleRoot)
            ? Path.Combine(repoRoot, "examples", "WGSExtract")
            : Path.GetFullPath(bundleRoot);
        if (!Directory.Exists(bundleRoot))
        {
            throw new InvalidOperationException($"Missing WebUI bundle: {bundleRoot}");
        }

        var nodeExecutable = ResolveNodeExecutable(repoRoot);
        return new WebViewShellRuntime(
            RepoRoot: repoRoot,
            NodeExecutable: nodeExecutable,
            ServerScriptPath: serverScriptPath,
            BundleRoot: bundleRoot,
            Host: host,
            Port: port,
            ExitAfterReady: exitAfterReady);
    }

    private static string ResolveRepoRoot()
    {
        var fromEnvironment = Environment.GetEnvironmentVariable("GFC_REPO_ROOT");
        if (!string.IsNullOrWhiteSpace(fromEnvironment))
        {
            var resolved = Path.GetFullPath(fromEnvironment);
            if (LooksLikeRepoRoot(resolved))
            {
                return resolved;
            }

            throw new InvalidOperationException($"GFC_REPO_ROOT is not a valid repository root: {resolved}");
        }

        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            if (LooksLikeRepoRoot(current.FullName))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        throw new InvalidOperationException(
            "Could not resolve repository root. Set GFC_REPO_ROOT for development runs.");
    }

    private static bool LooksLikeRepoRoot(string candidate) =>
        Directory.Exists(Path.Combine(candidate, "examples", "WGSExtract"))
        && File.Exists(Path.Combine(candidate, "platform", "typescript", "dist", "web", "src", "server", "main.js"));

    private static int ParsePort(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return 0;
        }

        if (int.TryParse(value, out var port) && port >= 0 && port <= ushort.MaxValue)
        {
            return port;
        }

        throw new InvalidOperationException($"Invalid GFC_PORT: {value}");
    }

    private static string ResolveNodeExecutable(string repoRoot)
    {
        var fromEnvironment = Environment.GetEnvironmentVariable("GFC_NODE_PATH");
        if (!string.IsNullOrWhiteSpace(fromEnvironment))
        {
            return Path.GetFullPath(fromEnvironment);
        }

        var bundledNode = Path.Combine(repoRoot, "node", "node.exe");
        if (File.Exists(bundledNode))
        {
            return bundledNode;
        }

        return "node";
    }

    private static bool IsEnabled(string? value) =>
        value is not null
        && (string.Equals(value, "1", StringComparison.OrdinalIgnoreCase)
            || string.Equals(value, "true", StringComparison.OrdinalIgnoreCase)
            || string.Equals(value, "yes", StringComparison.OrdinalIgnoreCase)
            || string.Equals(value, "on", StringComparison.OrdinalIgnoreCase));
}
