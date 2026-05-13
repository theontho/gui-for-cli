using System.Diagnostics;
using System.Text;

namespace GUIForCLIWindows.Core;

public sealed record ProcessExecutionRequest
{
    public required RenderedCommand Command { get; init; }
    public string? WorkingDirectory { get; init; }
    public IReadOnlyDictionary<string, string> Environment { get; init; } = new Dictionary<string, string>();
    public TimeSpan? Timeout { get; init; }
}

public sealed record ProcessExecutionResult(
    int ExitCode,
    string StandardOutput,
    string StandardError,
    bool TimedOut);

public static class WindowsCommandRouter
{
    public static ProcessStartInfo StartInfo(ProcessExecutionRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Command.Executable))
        {
            throw new ArgumentException("Command executable must not be empty.", nameof(request));
        }

        var startInfo = new ProcessStartInfo
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };

        if (!string.IsNullOrWhiteSpace(request.WorkingDirectory))
        {
            startInfo.WorkingDirectory = request.WorkingDirectory;
        }

        foreach (var (key, value) in request.Environment)
        {
            startInfo.Environment[key] = value;
        }

        Route(request.Command, startInfo);
        return startInfo;
    }

    private static void Route(RenderedCommand command, ProcessStartInfo startInfo)
    {
        var executable = command.Executable;
        var extension = Path.GetExtension(executable).ToLowerInvariant();
        switch (extension)
        {
            case ".ps1":
                startInfo.FileName = PowerShellExecutable();
                AddRange(startInfo.ArgumentList, ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", executable]);
                AddRange(startInfo.ArgumentList, command.Arguments);
                break;
            case ".sh" when OperatingSystem.IsWindows() && File.Exists(Path.ChangeExtension(executable, ".ps1")):
                startInfo.FileName = PowerShellExecutable();
                AddRange(startInfo.ArgumentList, ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Path.ChangeExtension(executable, ".ps1")]);
                AddRange(startInfo.ArgumentList, command.Arguments);
                break;
            case ".sh" when !OperatingSystem.IsWindows():
                startInfo.FileName = "/bin/sh";
                AddRange(startInfo.ArgumentList, [executable]);
                AddRange(startInfo.ArgumentList, command.Arguments);
                break;
            case ".cmd" when OperatingSystem.IsWindows():
            case ".bat" when OperatingSystem.IsWindows():
                startInfo.FileName = "cmd.exe";
                AddRange(startInfo.ArgumentList, ["/d", "/c", executable]);
                AddRange(startInfo.ArgumentList, command.Arguments);
                break;
            case ".py":
                startInfo.FileName = PythonExecutable();
                AddRange(startInfo.ArgumentList, [executable]);
                AddRange(startInfo.ArgumentList, command.Arguments);
                break;
            default:
                startInfo.FileName = executable;
                AddRange(startInfo.ArgumentList, command.Arguments);
                break;
        }
    }

    private static string PowerShellExecutable() =>
        !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("GUI_FOR_CLI_POWERSHELL"))
            ? Environment.GetEnvironmentVariable("GUI_FOR_CLI_POWERSHELL")!
            : OperatingSystem.IsWindows() ? "powershell.exe" : "pwsh";

    private static string PythonExecutable() =>
        !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("GUI_FOR_CLI_PYTHON"))
            ? Environment.GetEnvironmentVariable("GUI_FOR_CLI_PYTHON")!
            : OperatingSystem.IsWindows() ? "python.exe" : "python3";

    private static void AddRange(ICollection<string> target, IEnumerable<string> values)
    {
        foreach (var value in values)
        {
            target.Add(value);
        }
    }
}

public sealed class SimpleProcessRunner
{
    public async Task<ProcessExecutionResult> RunAsync(ProcessExecutionRequest request, CancellationToken cancellationToken = default)
    {
        using var process = new Process { StartInfo = WindowsCommandRouter.StartInfo(request), EnableRaisingEvents = true };
        var stdout = new StringBuilder();
        var stderr = new StringBuilder();
        process.OutputDataReceived += (_, args) =>
        {
            if (args.Data is not null)
            {
                stdout.AppendLine(args.Data);
            }
        };
        process.ErrorDataReceived += (_, args) =>
        {
            if (args.Data is not null)
            {
                stderr.AppendLine(args.Data);
            }
        };

        using var jobObject = WindowsJobObject.TryCreateKillOnClose();
        if (!process.Start())
        {
            throw new InvalidOperationException($"Could not start process: {request.Command.Executable}");
        }

        jobObject?.TryAssign(process);
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        using var timeoutSource = request.Timeout is { } timeout ? new CancellationTokenSource(timeout) : null;
        using var linkedSource = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            timeoutSource?.Token ?? CancellationToken.None);

        try
        {
            await process.WaitForExitAsync(linkedSource.Token).ConfigureAwait(false);
            return new ProcessExecutionResult(process.ExitCode, stdout.ToString(), stderr.ToString(), TimedOut: false);
        }
        catch (OperationCanceledException) when (timeoutSource?.IsCancellationRequested == true && !cancellationToken.IsCancellationRequested)
        {
            KillProcessTree(process);
            return new ProcessExecutionResult(-1, stdout.ToString(), stderr.ToString(), TimedOut: true);
        }
        catch
        {
            KillProcessTree(process);
            throw;
        }
    }

    private static void KillProcessTree(Process process)
    {
        if (!process.HasExited)
        {
            process.Kill(entireProcessTree: true);
        }
    }
}
