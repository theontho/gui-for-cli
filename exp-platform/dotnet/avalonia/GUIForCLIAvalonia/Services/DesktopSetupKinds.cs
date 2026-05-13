using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Services;

public static class DesktopSetupKinds
{
    public static RenderedCommand? CommandFor(SetupStepSpec step)
    {
        if (step.Command is not null)
        {
            return new RenderedCommand(step.Command.Executable, step.Command.Arguments);
        }

        return step.Kind switch
        {
            "pathTool" when !string.IsNullOrWhiteSpace(step.Value) => PathToolCommand(step.Value),
            "setupScript" when !string.IsNullOrWhiteSpace(step.Value) => SetupScriptCommand(step.Value, step.Arguments),
            "pixiRun" when !string.IsNullOrWhiteSpace(step.Value) => new RenderedCommand(PixiExecutable(), ["run", step.Value, .. step.Arguments]),
            "pixi" => new RenderedCommand(PixiExecutable(), ["--version"]),
            "powershellScript" when !string.IsNullOrWhiteSpace(step.Script ?? step.Value) => new RenderedCommand(step.Script ?? step.Value!, step.Arguments),
            _ => null,
        };
    }

    private static RenderedCommand PathToolCommand(string tool) =>
        OperatingSystem.IsWindows()
            ? new RenderedCommand("where.exe", [tool])
            : new RenderedCommand("/bin/sh", ["-lc", $"command -v {RenderingEngine.ShellQuote(tool)}"]);

    private static RenderedCommand SetupScriptCommand(string script, IReadOnlyList<string> arguments)
    {
        if (OperatingSystem.IsWindows())
        {
            return new RenderedCommand(Path.ChangeExtension(script, ".ps1"), arguments);
        }

        return new RenderedCommand(script, arguments);
    }

    private static string PixiExecutable() => OperatingSystem.IsWindows() ? "pixi.exe" : "pixi";
}
