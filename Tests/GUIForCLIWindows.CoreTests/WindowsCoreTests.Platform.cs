using GUIForCLIWindows.Core;

internal static partial class WindowsCoreTests
{
static void RoutesWindowsCommands()
{
    var direct = WindowsCommandRouter.StartInfo(new ProcessExecutionRequest
    {
        Command = new RenderedCommand("tool.exe", ["a value", "--flag"]),
    });
    Equal("tool.exe", direct.FileName);
    Equal("a value", direct.ArgumentList[0]);
    Equal("--flag", direct.ArgumentList[1]);

    var batch = WindowsCommandRouter.StartInfo(new ProcessExecutionRequest
    {
        Command = new RenderedCommand("setup.cmd", ["arg"]),
    });
    Equal("cmd.exe", batch.FileName);
    Equal("/d", batch.ArgumentList[0]);
    Equal("/c", batch.ArgumentList[1]);
    Equal("setup.cmd", batch.ArgumentList[2]);
    Equal("arg", batch.ArgumentList[3]);

    var python = WindowsCommandRouter.StartInfo(new ProcessExecutionRequest
    {
        Command = new RenderedCommand("source.py", ["options"]),
    });
    Equal("python.exe", python.FileName);
    Equal("source.py", python.ArgumentList[0]);
    Equal("options", python.ArgumentList[1]);

    Environment.SetEnvironmentVariable("GUI_FOR_CLI_POWERSHELL", "powershell.exe");
    try
    {
        var script = WindowsCommandRouter.StartInfo(new ProcessExecutionRequest
        {
            Command = new RenderedCommand("setup.ps1", ["-Mode", "quiet"]),
        });
        Equal("powershell.exe", script.FileName);
        Equal("-NoProfile", script.ArgumentList[0]);
        Equal("-File", script.ArgumentList[4]);
        Equal("setup.ps1", script.ArgumentList[5]);
        Equal("-Mode", script.ArgumentList[6]);
        Equal("quiet", script.ArgumentList[7]);
    }
    finally
    {
        Environment.SetEnvironmentVariable("GUI_FOR_CLI_POWERSHELL", null);
    }
}

static async Task RoutesShellScriptsToPowerShellSiblings()
{
    var root = Path.Combine(Path.GetTempPath(), "gui-for-cli-routing-tests", Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(root);
    var shellScript = Path.Combine(root, "tool.sh");
    var powerShellScript = Path.Combine(root, "tool.ps1");
    await File.WriteAllTextAsync(shellScript, "#!/bin/sh\n");
    await File.WriteAllTextAsync(powerShellScript, "'ps1:' + ($args -join ',')\n");

    Environment.SetEnvironmentVariable("GUI_FOR_CLI_POWERSHELL", "pwsh.exe");
    try
    {
        var info = WindowsCommandRouter.StartInfo(new ProcessExecutionRequest
        {
            Command = new RenderedCommand(shellScript, ["a", "b"]),
        });
        Equal("pwsh.exe", info.FileName);
        Equal(powerShellScript, info.ArgumentList[5]);

        var result = await new SimpleProcessRunner().RunAsync(new ProcessExecutionRequest
        {
            Command = new RenderedCommand(shellScript, ["a", "b"]),
            Timeout = TimeSpan.FromSeconds(10),
        });
        Equal(0, result.ExitCode);
        Equal("ps1:a,b", result.StandardOutput.Trim());
    }
    finally
    {
        Environment.SetEnvironmentVariable("GUI_FOR_CLI_POWERSHELL", null);
    }
}

static void MapsSemanticIconsToFluentGlyphs()
{
    Equal("\uE713", WindowsIconMapper.GlyphFor("gear"));
    Equal("\uE756", WindowsIconMapper.GlyphFor("terminal"));
    Equal("\uECAA", WindowsIconMapper.GlyphFor("missing-symbol"));
}

static void BuildsWindowsSetupCommands()
{
    Equal(true, WindowsSetupKinds.IsWindowsNative(WindowsSetupKinds.PowershellScript));
    var script = WindowsSetupKinds.CommandFor(new SetupStepSpec
    {
        Kind = WindowsSetupKinds.PowershellScript,
        Script = "scripts/setup.ps1",
    });
    Equal("scripts/setup.ps1", script!.Executable);

    var package = WindowsSetupKinds.CommandFor(new SetupStepSpec
    {
        Kind = WindowsSetupKinds.WingetPackage,
        PackageId = "Prefix.Tool",
    });
    Equal("winget.exe", package!.Executable);
    SequenceEqual(["list", "--id", "Prefix.Tool", "--exact"], package.Arguments);

    var pixi = WindowsSetupKinds.CommandFor(new SetupStepSpec { Kind = WindowsSetupKinds.Pixi });
    Equal("pixi.exe", pixi!.Executable);
    SequenceEqual(["--version"], pixi.Arguments);
}

static void ExposesWindowsProcessHardeningPrimitives()
{
    Equal(OperatingSystem.IsWindows(), WindowsJobObject.IsSupported);
    if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 17763))
    {
        Equal(true, ConPtyProcessRunner.IsAvailable);
    }
}

static async Task RunsBundleDataSourceAndFileState()
{
    var root = Path.Combine(Path.GetTempPath(), "gui-for-cli-runtime-tests", Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(Path.Combine(root, "scripts"));
    var script = Path.Combine(root, "scripts", "options.cmd");
    await File.WriteAllTextAsync(script, "@echo {^\"options^\":[{^\"id^\":^\"hg38^\",^\"title^\":^\"GRCh38^\"}]}\r\n");
    var data = Path.Combine(root, "sample.sorted.bam");
    await File.WriteAllTextAsync(data, "bam");
    await File.WriteAllTextAsync($"{data}.bai", "index");

    var service = new BundleRuntimeService(new SimpleProcessRunner());
    var payload = await service.RunDataSourceAsync(new DataSourceSpec
    {
        Path = "scripts/options.cmd",
        Arguments = ["{{mode}}"],
    }, new RenderContext
    {
        BundleRootPath = root,
        FieldValues = new Dictionary<string, string> { ["mode"] = "options" },
    }, root);
    Equal("hg38", payload.Options![0].Id);

    var state = await service.FileStateValuesAsync(new RenderContext
    {
        FieldValues = new Dictionary<string, string> { ["alignment"] = data },
    }, root);
    Equal("true", state["alignment.exists"]);
    Equal("bam", state["alignment.pathExtension"]);
    Equal("true", state["alignment.isIndexed"]);
    Equal("true", state["alignment.isSorted"]);
}

static async Task RunsSimpleRedirectedProcess()
{
    var result = await new SimpleProcessRunner().RunAsync(new ProcessExecutionRequest
    {
        Command = new RenderedCommand("cmd.exe", ["/d", "/c", "echo", "gui-for-cli"]),
        Timeout = TimeSpan.FromSeconds(10),
    });

    Equal(0, result.ExitCode);
    Equal(false, result.TimedOut);
    Equal("gui-for-cli", result.StandardOutput.Trim());
}

}
