using System.ComponentModel;
using System.Diagnostics;
using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Services;

public sealed record DesktopProcessResult(int ExitCode, bool Cancelled, bool TimedOut);

public sealed class DesktopProcessRunner
{
    public async Task<DesktopProcessResult> RunAsync(
        RenderedCommand command,
        string workingDirectory,
        IReadOnlyDictionary<string, string> environment,
        Action<string> appendOutput,
        CancellationToken cancellationToken = default,
        TimeSpan? timeout = null)
    {
        var startInfo = StartInfo(command, workingDirectory, environment);
        using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        process.OutputDataReceived += (_, args) => AppendLine(args.Data, appendOutput);
        process.ErrorDataReceived += (_, args) => AppendLine(args.Data, appendOutput);

        if (!process.Start())
        {
            throw new InvalidOperationException($"Could not start process: {command.Executable}");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        using var timeoutSource = timeout is null ? null : new CancellationTokenSource(timeout.Value);
        using var linkedSource = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            timeoutSource?.Token ?? CancellationToken.None);

        try
        {
            await process.WaitForExitAsync(linkedSource.Token).ConfigureAwait(false);
            return new DesktopProcessResult(process.ExitCode, Cancelled: false, TimedOut: false);
        }
        catch (OperationCanceledException)
        {
            KillProcessTree(process);
            return new DesktopProcessResult(-1, cancellationToken.IsCancellationRequested, timeoutSource?.IsCancellationRequested == true);
        }
    }

    private static ProcessStartInfo StartInfo(
        RenderedCommand command,
        string workingDirectory,
        IReadOnlyDictionary<string, string> environment)
    {
        if (string.IsNullOrWhiteSpace(command.Executable))
        {
            throw new ArgumentException("Command executable must not be empty.", nameof(command));
        }

        var startInfo = new ProcessStartInfo
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = string.IsNullOrWhiteSpace(workingDirectory) ? Environment.CurrentDirectory : workingDirectory,
        };

        foreach (var (key, value) in environment)
        {
            startInfo.Environment[key] = value;
        }

        Route(command, startInfo);
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
                break;
            case ".cmd":
            case ".bat":
                if (OperatingSystem.IsWindows())
                {
                    startInfo.FileName = "cmd.exe";
                    AddRange(startInfo.ArgumentList, ["/d", "/c", executable]);
                }
                else
                {
                    startInfo.FileName = executable;
                }
                break;
            case ".py":
                startInfo.FileName = PythonExecutable();
                startInfo.ArgumentList.Add(executable);
                break;
            case ".sh" when !OperatingSystem.IsWindows():
                startInfo.FileName = "/bin/sh";
                startInfo.ArgumentList.Add(executable);
                break;
            default:
                startInfo.FileName = executable;
                break;
        }

        AddRange(startInfo.ArgumentList, command.Arguments);
    }

    private static string PowerShellExecutable() =>
        Environment.GetEnvironmentVariable("GUI_FOR_CLI_POWERSHELL")
        ?? (OperatingSystem.IsWindows() ? "powershell.exe" : "pwsh");

    private static string PythonExecutable() =>
        Environment.GetEnvironmentVariable("GUI_FOR_CLI_PYTHON")
        ?? (OperatingSystem.IsWindows() ? "python.exe" : "python3");

    private static void AddRange(ICollection<string> target, IEnumerable<string> values)
    {
        foreach (var value in values)
        {
            target.Add(value);
        }
    }

    private static void AppendLine(string? line, Action<string> appendOutput)
    {
        if (line is not null)
        {
            appendOutput(line);
        }
    }

    private static void KillProcessTree(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (InvalidOperationException)
        {
        }
        catch (Win32Exception)
        {
        }
    }
}
