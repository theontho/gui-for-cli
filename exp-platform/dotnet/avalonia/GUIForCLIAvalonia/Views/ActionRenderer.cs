using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Media;
using GUIForCLIAvalonia.Services;
using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Views;

public sealed class ActionRenderer
{
    private readonly DesktopBundleSession _session;
    private readonly TerminalManager _terminal;
    private readonly Window _owner;
    private readonly Func<Task> _refresh;

    public ActionRenderer(DesktopBundleSession session, TerminalManager terminal, Window owner, Func<Task> refresh)
    {
        _session = session;
        _terminal = terminal;
        _owner = owner;
        _refresh = refresh;
    }

    public Control Render(ActionSpec action, RenderContext context)
    {
        var button = new Button { Content = action.Title, MinWidth = 96 };
        if (action.Destructive)
        {
            button.Foreground = Brushes.Firebrick;
        }

        AutomationProperties.SetName(button, action.Title);
        ApplyState(button, action, context);
        button.Click += async (_, _) => await RunAsync(button, action, context);
        return button;
    }

    private void ApplyState(Button button, ActionSpec action, RenderContext context)
    {
        var missing = RenderingEngine.MissingPlaceholders(action.Command, context);
        var disabledReason = RenderingEngine.DisabledReason(action, context);
        var visible = RenderingEngine.IsActionVisible(action, context);
        button.IsVisible = visible;
        button.IsEnabled = visible && missing.Count == 0 && disabledReason is null;
        var tooltip = missing.Count > 0
            ? $"Required: {string.Join(", ", ActionDisplayNames.ForPlaceholders(_session.Manifest, missing))}"
            : disabledReason ?? action.Tooltip ?? action.Title;
        ToolTip.SetTip(button, tooltip);
    }

    private async Task RunAsync(Button button, ActionSpec action, RenderContext context)
    {
        try
        {
            if (!await ConfirmationDialog.ShowAsync(_owner, action))
            {
                _terminal.AppendGeneral($"Cancelled {action.Title}.");
                return;
            }

            button.IsEnabled = false;
            await _terminal.RunActionAsync(action, context, _session.BundleRoot, _session.BundleWorkspace, _refresh);
        }
        catch (Exception error)
        {
            _terminal.AppendGeneral($"Error running {action.Title}: {error.Message}");
        }
        finally
        {
            ApplyState(button, action, context);
        }
    }
}
