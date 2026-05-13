using System.Text;

namespace GUIForCLIAvalonia.Models;

public sealed class TerminalTab
{
    private readonly StringBuilder _output = new();
    private readonly object _outputLock = new();

    public TerminalTab(string id, string title, bool closeable)
    {
        Id = id;
        Title = title;
        IsCloseable = closeable;
    }

    public string Id { get; }
    public string Title { get; set; }
    public bool IsCloseable { get; }
    public bool IsRunning { get; set; }
    public int? ExitCode { get; set; }
    public string Status { get; set; } = "idle";
    public CancellationTokenSource? Cancellation { get; set; }
    public string Output
    {
        get
        {
            lock (_outputLock)
            {
                return _output.ToString();
            }
        }
    }
    public event Action<TerminalTab>? Changed;

    public void Append(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return;
        }

        lock (_outputLock)
        {
            _output.AppendLine(text.TrimEnd());
        }

        Changed?.Invoke(this);
    }

    public void NotifyChanged() => Changed?.Invoke(this);
}
