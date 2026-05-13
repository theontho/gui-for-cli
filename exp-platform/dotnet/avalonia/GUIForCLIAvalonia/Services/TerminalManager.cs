using Avalonia.Threading;
using GUIForCLIAvalonia.Models;
using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Services;

public sealed class TerminalManager
{
    private readonly DesktopProcessRunner _runner = new();
    private int _nextTabID = 1;

    public TerminalManager()
    {
        GeneralTab = new TerminalTab("general", "General", closeable: false);
        Tabs.Add(GeneralTab);
        SelectedTab = GeneralTab;
    }

    public List<TerminalTab> Tabs { get; } = [];
    public TerminalTab GeneralTab { get; }
    public TerminalTab SelectedTab { get; private set; }
    public event Action? Changed;

    public void Select(TerminalTab tab)
    {
        SelectedTab = tab;
        Changed?.Invoke();
    }

    public void Close(TerminalTab tab)
    {
        if (!tab.IsCloseable)
        {
            return;
        }

        if (tab.IsRunning)
        {
            tab.Cancellation?.Cancel();
        }

        Tabs.Remove(tab);
        if (SelectedTab == tab)
        {
            SelectedTab = Tabs.LastOrDefault() ?? GeneralTab;
        }

        Changed?.Invoke();
    }

    public async Task RunActionAsync(
        ActionSpec action,
        RenderContext context,
        string bundleRoot,
        string bundleWorkspace,
        Func<Task> afterFinished)
    {
        var tab = CreateTab(action.Title);
        var precheck = PrecheckEvaluator.Describe(action.Precheck, context);
        if (precheck is not null)
        {
            tab.Append(precheck);
        }

        tab.Append($"> {RenderingEngine.DisplayCommand(action.Command, context)}");
        var command = RenderingEngine.RenderedCommand(action.Command, context);
        await RunCommandInTabAsync(tab, command, bundleRoot, bundleRoot, bundleWorkspace, TimeSpan.FromHours(12)).ConfigureAwait(false);
        await afterFinished().ConfigureAwait(false);
    }

    public async Task<BundleSetupRunState> RunSetupAsync(DesktopBundleSession session)
    {
        var tab = CreateTab("Setup");
        tab.Append("Running bundle setup...");
        var results = new List<BundleSetupStepRunState>();
        foreach (var step in session.Manifest.Setup.Steps)
        {
            var command = DesktopSetupKinds.CommandFor(step);
            if (command is null)
            {
                results.Add(SetupResult(step, null, "skipped", null));
                continue;
            }

            var resolved = new RenderedCommand(
                RenderingEngine.Interpolate(command.Executable, session.CommandContext()),
                command.Arguments.Select(arg => RenderingEngine.Interpolate(arg, session.CommandContext())).ToList());
            var workingDirectory = string.IsNullOrWhiteSpace(step.WorkingDirectory)
                ? session.BundleRoot
                : BundleRuntimeService.ResolveBundlePath(step.WorkingDirectory, session.BundleRoot);
            tab.Append($"> {step.Label}: {resolved.Executable} {string.Join(" ", resolved.Arguments)}");
            var result = await RunCommandInTabAsync(tab, resolved, session.BundleRoot, workingDirectory, session.BundleWorkspace, TimeSpan.FromMinutes(30), step.Environment).ConfigureAwait(false);
            var status = result.ExitCode == 0 || step.Optional ? "ok" : "failed";
            results.Add(SetupResult(step, resolved, status, result.ExitCode));
            if (status == "failed")
            {
                break;
            }
        }

        var failed = results.FirstOrDefault(result => result.Status == "failed");
        return new BundleSetupRunState
        {
            Status = failed is null ? "ok" : "failed",
            Results = results,
            CompletedAt = DateTimeOffset.UtcNow.ToString("O"),
            Error = failed is null ? null : $"{failed.Label} failed.",
        };
    }

    public void AppendGeneral(string message)
    {
        GeneralTab.Append(message);
        Select(GeneralTab);
    }

    private TerminalTab CreateTab(string title)
    {
        var tab = new TerminalTab($"tab-{_nextTabID++}", title, closeable: true) { IsRunning = true, Status = "running" };
        tab.Cancellation = new CancellationTokenSource();
        Tabs.Add(tab);
        SelectedTab = tab;
        Changed?.Invoke();
        return tab;
    }

    private async Task<DesktopProcessResult> RunCommandInTabAsync(
        TerminalTab tab,
        RenderedCommand command,
        string bundleRoot,
        string workingDirectory,
        string bundleWorkspace,
        TimeSpan timeout,
        IReadOnlyDictionary<string, string>? extraEnvironment = null)
    {
        var env = new Dictionary<string, string>(extraEnvironment ?? new Dictionary<string, string>())
        {
            ["GUI_FOR_CLI_BUNDLE_ROOT"] = bundleRoot,
            ["GUI_FOR_CLI_BUNDLE_WORKSPACE"] = bundleWorkspace,
        };
        PrepareTabForCommand(tab);

        try
        {
            var result = await _runner.RunAsync(
                command,
                workingDirectory,
                env,
                line => Dispatcher.UIThread.Post(() => tab.Append(line)),
                tab.Cancellation?.Token ?? CancellationToken.None,
                timeout).ConfigureAwait(false);
            Dispatcher.UIThread.Post(() => CompleteTab(tab, result));
            return result;
        }
        catch (Exception error)
        {
            var result = new DesktopProcessResult(-1, Cancelled: false, TimedOut: false);
            Dispatcher.UIThread.Post(() =>
            {
                tab.Append($"Action failed: {error.Message}");
                tab.Status = "failed";
                tab.IsRunning = false;
                tab.NotifyChanged();
                Changed?.Invoke();
            });
            return result;
        }
    }

    private static void PrepareTabForCommand(TerminalTab tab)
    {
        tab.ExitCode = null;
        tab.IsRunning = true;
        tab.Status = "running";
        tab.NotifyChanged();
    }

    private void CompleteTab(TerminalTab tab, DesktopProcessResult result)
    {
        tab.ExitCode = result.ExitCode;
        tab.Status = result.Cancelled ? "cancelled" : result.TimedOut ? "timed out" : result.ExitCode == 0 ? "ok" : "failed";
        tab.IsRunning = false;
        tab.Append($"Exit code: {result.ExitCode} ({tab.Status})");
        tab.NotifyChanged();
        Changed?.Invoke();
    }

    private static BundleSetupStepRunState SetupResult(SetupStepSpec step, RenderedCommand? command, string status, int? exitCode) => new()
    {
        Id = step.Id,
        Label = step.Label,
        Kind = step.Kind,
        Command = command is null ? null : $"{command.Executable} {string.Join(" ", command.Arguments)}".Trim(),
        Status = status,
        ExitCode = exitCode,
    };
}
