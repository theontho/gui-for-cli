using System.Diagnostics;
using System.Net.Http;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;

namespace GUIForCLIWindows;

public sealed partial class WebViewShellWindow : Window
{
    private static readonly TimeSpan StartupTimeout = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan PollDelay = TimeSpan.FromMilliseconds(25);
    private static readonly HttpClient HttpClient = new() { Timeout = TimeSpan.FromMilliseconds(250) };

    private readonly Stopwatch _startupStopwatch = Stopwatch.StartNew();
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private readonly WebViewShellRuntime _runtime;
    private Process? _nodeProcess;
    private bool _reportedWindowShown;
    private bool _reportedNavigationFinished;
    private bool _reportedRendered;

    public WebViewShellWindow()
    {
        _runtime = WebViewShellRuntime.Resolve();
        InitializeComponent();
        Activated += OnActivated;
        Closed += OnClosed;
        _ = StartAsync();
    }

    private async Task StartAsync()
    {
        try
        {
            PrintMetric("appSetupStarted");
            var port = await LaunchNodeServerAsync();
            await WaitForManifestAsync(port, _lifetimeCancellation.Token);
            PrintMetric("serverManifestReady");
            await WebView.EnsureCoreWebView2Async();
            WebView.Source = new Uri($"http://{_runtime.Host}:{port}/");
        }
        catch (Exception error)
        {
            Console.Error.WriteLine($"error={error.Message}");
            Console.Error.Flush();
            App.Current.Exit();
        }
    }

    private void OnActivated(object sender, WindowActivatedEventArgs args)
    {
        if (_reportedWindowShown)
        {
            return;
        }

        _reportedWindowShown = true;
        PrintMetric("windowShown");
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        _lifetimeCancellation.Cancel();
        try
        {
            if (_nodeProcess is { HasExited: false })
            {
                _nodeProcess.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // Best-effort cleanup only.
        }
        finally
        {
            _nodeProcess?.Dispose();
            _lifetimeCancellation.Dispose();
        }
    }

    private async Task<int> LaunchNodeServerAsync()
    {
        var useDynamicPort = _runtime.Port == 0;
        var portFilePath = useDynamicPort
            ? Path.Combine(Path.GetTempPath(), $"gui-for-cli-webview2-{Guid.NewGuid():N}.port")
            : null;

        var startInfo = new ProcessStartInfo
        {
            FileName = _runtime.NodeExecutable,
            WorkingDirectory = _runtime.RepoRoot,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        startInfo.ArgumentList.Add(_runtime.ServerScriptPath);
        startInfo.ArgumentList.Add("--port");
        startInfo.ArgumentList.Add(_runtime.Port.ToString());
        startInfo.ArgumentList.Add("--host");
        startInfo.ArgumentList.Add(_runtime.Host);
        startInfo.ArgumentList.Add("--bundle");
        startInfo.ArgumentList.Add(_runtime.BundleRoot);
        startInfo.Environment["GFC_PARENT_PID"] = Environment.ProcessId.ToString();
        if (portFilePath is not null)
        {
            startInfo.Environment["GFC_PORT_FILE"] = portFilePath;
        }

        var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Failed to launch Node process.");
        _nodeProcess = process;
        Console.WriteLine($"node_pid={process.Id}");
        Console.Out.Flush();
        PrintMetric("nodeProcessStarted");

        if (!useDynamicPort)
        {
            return _runtime.Port;
        }

        return await WaitForPortFileAsync(portFilePath!, _lifetimeCancellation.Token);
    }

    private async Task<int> WaitForPortFileAsync(string portFilePath, CancellationToken cancellationToken)
    {
        var deadline = DateTimeOffset.UtcNow + StartupTimeout;
        while (DateTimeOffset.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();

            if (File.Exists(portFilePath))
            {
                try
                {
                    var contents = await File.ReadAllTextAsync(portFilePath, cancellationToken);
                    if (int.TryParse(contents.Trim(), out var port) && port > 0)
                    {
                        File.Delete(portFilePath);
                        return port;
                    }
                }
                catch (IOException)
                {
                    // Port file may still be in-flight; retry.
                }
                catch (UnauthorizedAccessException)
                {
                    // Port file may still be in-flight; retry.
                }
            }

            await Task.Delay(PollDelay, cancellationToken);
        }

        throw new TimeoutException($"Timed out waiting for WebUI port file: {portFilePath}");
    }

    private async Task WaitForManifestAsync(int port, CancellationToken cancellationToken)
    {
        var uri = new Uri($"http://{_runtime.Host}:{port}/api/manifest");
        var deadline = DateTimeOffset.UtcNow + StartupTimeout;
        while (DateTimeOffset.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                using var response = await HttpClient.GetAsync(uri, cancellationToken);
                if (response.IsSuccessStatusCode)
                {
                    return;
                }
            }
            catch
            {
                // Retry until startup timeout.
            }

            await Task.Delay(PollDelay, cancellationToken);
        }

        throw new TimeoutException("Timed out waiting for /api/manifest.");
    }

    private async void WebView_NavigationCompleted(WebView2 sender, CoreWebView2NavigationCompletedEventArgs args)
    {
        if (!_reportedNavigationFinished)
        {
            _reportedNavigationFinished = true;
            PrintMetric("webNavigationDidFinish");
        }

        if (_reportedRendered)
        {
            return;
        }

        var deadline = DateTimeOffset.UtcNow + StartupTimeout;
        while (DateTimeOffset.UtcNow < deadline)
        {
            var isReady = await IsWebAppReadyAsync();
            if (isReady)
            {
                _reportedRendered = true;
                PrintMetric("webAppRendered");
                if (_runtime.ExitAfterReady)
                {
                    App.Current.Exit();
                }
                return;
            }

            await Task.Delay(PollDelay);
        }

        Console.Error.WriteLine("error=Timed out waiting for rendered WebUI.");
        Console.Error.Flush();
        App.Current.Exit();
    }

    private async Task<bool> IsWebAppReadyAsync()
    {
        var rawResult = await WebView.ExecuteScriptAsync(
            "Boolean(document.querySelector('#app')?.dataset.state === 'ready' && document.title)");
        return string.Equals(rawResult, "true", StringComparison.OrdinalIgnoreCase);
    }

    private void PrintMetric(string name)
    {
        Console.WriteLine($"metric {name}_ms={_startupStopwatch.Elapsed.TotalMilliseconds:F1}");
        Console.Out.Flush();
    }
}
