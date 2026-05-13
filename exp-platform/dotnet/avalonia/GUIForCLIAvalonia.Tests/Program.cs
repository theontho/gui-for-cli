using System.Text.Json;
using GUIForCLIAvalonia.Services;
using GUIForCLIWindows.Core;

var tests = new List<(string Name, Action Body)>
{
    ("layout detects RTL locales", TestRtlLayout),
    ("render context separates bundle root and workspace", TestBundleWorkspacePlaceholder),
    ("data source payload carries section values", TestDataSourceValues),
    ("desktop setup maps generic setup kinds", TestSetupKinds),
    ("app path uses safe bundle workspace", TestSafeWorkspace),
};

var failures = new List<string>();
foreach (var (name, body) in tests)
{
    try
    {
        body();
        Console.WriteLine($"ok - {name}");
    }
    catch (Exception error)
    {
        failures.Add($"{name}: {error.Message}");
        Console.Error.WriteLine($"not ok - {name}: {error.Message}");
    }
}

if (failures.Count > 0)
{
    Console.Error.WriteLine($"{failures.Count} Avalonia renderer test(s) failed.");
    return 1;
}

Console.WriteLine($"All {tests.Count} Avalonia renderer tests passed.");
return 0;

static void TestRtlLayout()
{
    True(LayoutDirection.IsRtlLocale("ar"));
    True(LayoutDirection.IsRtlLocale("he-IL"));
    False(LayoutDirection.IsRtlLocale("en-US"));
}

static void TestBundleWorkspacePlaceholder()
{
    var context = new RenderContext { BundleRootPath = "/bundle", BundleWorkspacePath = "/workspace" };
    Equal("/bundle", RenderingEngine.Interpolate("{{bundleRoot}}", context));
    Equal("/workspace", RenderingEngine.Interpolate("{{bundleWorkspace}}", context));
}

static void TestDataSourceValues()
{
    var payload = JsonSerializer.Deserialize<DataSourcePayload>("{\"values\":{\"library.isBootstrapped\":\"true\"}}");
    Equal("true", payload?.Values?["library.isBootstrapped"]);
}

static void TestSetupKinds()
{
    var pathTool = DesktopSetupKinds.CommandFor(new SetupStepSpec { Kind = "pathTool", Value = "pixi" });
    True(pathTool is not null);
    var setup = DesktopSetupKinds.CommandFor(new SetupStepSpec { Kind = "setupScript", Value = "scripts/setup.sh", Arguments = ["--quiet"] });
    Equal("scripts/setup.sh", setup?.Executable);
    Equal("--quiet", setup?.Arguments.FirstOrDefault());
}

static void TestSafeWorkspace()
{
    Environment.SetEnvironmentVariable("GUI_FOR_CLI_CONFIG_DIR", Path.Combine(Directory.GetCurrentDirectory(), "tmp", "avalonia-tests"));
    var paths = AvaloniaAppPaths.ForCurrentUser();
    var workspace = paths.BundleWorkspace("bad/name?with*chars");
    True(workspace.Contains("bad-name-with-chars", StringComparison.Ordinal));
    Environment.SetEnvironmentVariable("GUI_FOR_CLI_CONFIG_DIR", null);
}

static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"expected '{expected}', got '{actual}'");
    }
}

static void True(bool value)
{
    if (!value)
    {
        throw new InvalidOperationException("expected true");
    }
}

static void False(bool value)
{
    if (value)
    {
        throw new InvalidOperationException("expected false");
    }
}
