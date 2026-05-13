using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using GUIForCLIAvalonia.Models;
using GUIForCLIAvalonia.Services;
using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Views;

public sealed class TerminalPane
{
    private readonly TerminalManager _terminal;
    private readonly TextBox _output = new()
    {
        IsReadOnly = true,
        AcceptsReturn = true,
        TextWrapping = TextWrapping.NoWrap,
        FontFamily = FontFamily.Parse("Menlo, Consolas, monospace"),
    };
    private readonly StackPanel _tabs = new() { Orientation = Orientation.Horizontal, Spacing = 6 };
    private readonly Border _root = new();
    private bool _isVisible = true;
    private BundleManifest? _manifest;

    public TerminalPane(TerminalManager terminal)
    {
        _terminal = terminal;
        _terminal.Changed += Rebuild;
        _root.Child = BuildRootContent();
        AutomationProperties.SetName(_output, "Terminal output");
        Rebuild();
    }

    public Control Control => _root;

    public void ApplyManifest(BundleManifest manifest)
    {
        _manifest = manifest;
        _output.FlowDirection = LayoutDirection.TerminalDirection(manifest);
    }

    private Control BuildRootContent()
    {
        var panel = new DockPanel { LastChildFill = true };
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto"), Margin = new Thickness(8, 6) };
        header.Children.Add(_tabs);
        var toggle = new Button { Content = "▾", MinWidth = 34 };
        AutomationProperties.SetName(toggle, "Hide or show terminal");
        toggle.Click += (_, _) =>
        {
            _isVisible = !_isVisible;
            _output.IsVisible = _isVisible;
            toggle.Content = _isVisible ? "▾" : "▴";
        };
        Grid.SetColumn(toggle, 1);
        header.Children.Add(toggle);
        DockPanel.SetDock(header, Dock.Top);
        panel.Children.Add(header);
        panel.Children.Add(_output);
        return panel;
    }

    private void Rebuild()
    {
        _tabs.Children.Clear();
        foreach (var tab in _terminal.Tabs.ToList())
        {
            tab.Changed -= OnTabChanged;
            tab.Changed += OnTabChanged;
            var title = tab.IsRunning ? $"⏳ {tab.Title}" : StatusPrefix(tab) + tab.Title;
            var button = new Button
            {
                Content = title,
                MinWidth = 80,
                FontWeight = _terminal.SelectedTab == tab ? FontWeight.SemiBold : FontWeight.Normal,
            };
            AutomationProperties.SetName(button, $"Terminal tab {tab.Title} {tab.Status}");
            button.Click += (_, _) => _terminal.Select(tab);
            _tabs.Children.Add(button);

            if (tab.IsCloseable)
            {
                var close = new Button { Content = tab.IsRunning ? "Cancel" : "×", MinWidth = 34 };
                AutomationProperties.SetName(close, tab.IsRunning ? $"Cancel {tab.Title}" : $"Close {tab.Title}");
                close.Click += (_, _) => _terminal.Close(tab);
                _tabs.Children.Add(close);
            }
        }

        _output.Text = _terminal.SelectedTab.Output;
        if (_manifest is not null)
        {
            _output.FlowDirection = LayoutDirection.TerminalDirection(_manifest);
        }
        _output.CaretIndex = _output.Text?.Length ?? 0;
    }

    private void OnTabChanged(TerminalTab tab)
    {
        if (_terminal.SelectedTab == tab)
        {
            _output.Text = tab.Output;
            _output.CaretIndex = _output.Text?.Length ?? 0;
        }
    }

    private static string StatusPrefix(TerminalTab tab) => tab.Status switch
    {
        "ok" => "✓ ",
        "failed" => "⚠ ",
        "cancelled" => "⏹ ",
        _ => "",
    };
}
