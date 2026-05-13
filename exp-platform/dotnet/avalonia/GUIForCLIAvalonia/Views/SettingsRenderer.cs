using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;
using GUIForCLIAvalonia.Services;
using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Views;

public sealed class SettingsRenderer
{
    private readonly DesktopBundleSession _session;
    private readonly TerminalManager _terminal;
    private readonly MainWindow _owner;
    private readonly Func<Task> _refresh;
    private readonly string? _selectedPageID;

    public SettingsRenderer(DesktopBundleSession session, TerminalManager terminal, MainWindow owner, string? selectedPageID, Func<Task> refresh)
    {
        _session = session;
        _terminal = terminal;
        _owner = owner;
        _selectedPageID = selectedPageID;
        _refresh = refresh;
    }

    public Control Render()
    {
        var panel = new StackPanel { Spacing = 12 };
        panel.Children.Add(AppearanceCard());
        panel.Children.Add(SetupCard());
        return panel;
    }

    private Control AppearanceCard()
    {
        var panel = Card("Appearance");
        var language = new ComboBox { MinWidth = 280 };
        var languageItems = new[] { new ComboBoxItem { Content = "Use system default", Tag = "" } }
            .Concat(_session.LocaleOptions.Select(option => new ComboBoxItem { Content = option.Name, Tag = option.Code }))
            .ToList();
        language.ItemsSource = languageItems;
        SelectByTag(language, _session.BundleState.LocalizationCode ?? "", languageItems);
        language.SelectionChanged += async (_, _) =>
        {
            if (language.SelectedItem is ComboBoxItem item)
            {
                await _session.SavePreferencesAsync(item.Tag?.ToString(), _session.BundleState.ColorTheme);
                await _owner.ReloadBundleForPreferencesAsync();
            }
        };
        AutomationProperties.SetName(language, "Language");
        panel.Children.Add(Labeled("Language", language, "Choose the interface language for this bundle."));

        var theme = new ComboBox { MinWidth = 220 };
        var themeItems = new[] { ("system", "System"), ("light", "Light"), ("dark", "Dark") }
            .Select(item => new ComboBoxItem { Content = item.Item2, Tag = item.Item1 })
            .ToList();
        theme.ItemsSource = themeItems;
        SelectByTag(theme, _session.BundleState.ColorTheme, themeItems);
        theme.SelectionChanged += async (_, _) =>
        {
            if (theme.SelectedItem is ComboBoxItem item)
            {
                await _session.SavePreferencesAsync(_session.BundleState.LocalizationCode, item.Tag?.ToString());
            }
        };
        panel.Children.Add(Labeled("Theme", theme, "Stored for the bundle workspace."));
        return panel;
    }

    private Control SetupCard()
    {
        var panel = Card(SetupStatusTitle());
        if (_session.Manifest.Setup.Steps.Count == 0)
        {
            panel.Children.Add(new TextBlock { Text = "No setup steps are defined for this bundle." });
        }
        else
        {
            foreach (var step in _session.Manifest.Setup.Steps)
            {
                var result = _session.BundleState.SetupRun?.Results.FirstOrDefault(candidate => candidate.Id == step.Id);
                panel.Children.Add(new TextBlock { Text = $"{step.Label}: {result?.Status ?? "not run"}" });
            }
        }

        var button = new Button { Content = _session.BundleState.SetupRun?.Status == "ok" ? "Run setup again" : "Run setup" };
        button.IsEnabled = _session.Manifest.Setup.Steps.Count > 0;
        button.Click += async (_, _) =>
        {
            var setupRun = await _terminal.RunSetupAsync(_session);
            await _session.SaveStateAsync(_selectedPageID, setupRun);
            await _refresh();
        };
        AutomationProperties.SetName(button, "Run setup");
        panel.Children.Add(button);
        return panel;
    }

    private string SetupStatusTitle() => _session.BundleState.SetupRun?.Status switch
    {
        "ok" => "Setup ready",
        "failed" => "Setup needs attention",
        _ => "Setup not run",
    };

    private static StackPanel Card(string title)
    {
        var panel = new StackPanel { Spacing = 10, Margin = new Thickness(0, 0, 0, 12) };
        panel.Children.Add(new TextBlock { Text = title, FontSize = 18, FontWeight = Avalonia.Media.FontWeight.SemiBold });
        return panel;
    }

    private static Control Labeled(string label, Control input, string tooltip)
    {
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(new TextBlock { Text = label, FontWeight = Avalonia.Media.FontWeight.SemiBold });
        panel.Children.Add(new TextBlock { Text = tooltip, Opacity = 0.72, TextWrapping = Avalonia.Media.TextWrapping.Wrap });
        panel.Children.Add(input);
        return panel;
    }

    private static void SelectByTag(ComboBox combo, string? tag, IReadOnlyList<ComboBoxItem> items)
    {
        combo.SelectedItem = items.FirstOrDefault(item => string.Equals(item.Tag?.ToString(), tag, StringComparison.Ordinal));
        if (combo.SelectedIndex < 0 && items.Count > 0)
        {
            combo.SelectedIndex = 0;
        }
    }
}
