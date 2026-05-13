using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using GUIForCLIAvalonia.Services;
using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Views;

public sealed class PageRenderer
{
    private readonly DesktopBundleSession _session;
    private readonly TerminalManager _terminal;
    private readonly MainWindow _owner;
    private readonly string? _selectedPageID;
    private readonly Func<Task> _refresh;

    public PageRenderer(DesktopBundleSession session, TerminalManager terminal, MainWindow owner, string? selectedPageID, Func<Task> refresh)
    {
        _session = session;
        _terminal = terminal;
        _owner = owner;
        _selectedPageID = selectedPageID;
        _refresh = refresh;
    }

    public Control Render(BundlePage page)
    {
        var panel = new StackPanel { Spacing = 12, Margin = new Thickness(24) };
        panel.Children.Add(Header(page));
        if (page.Id == "settings")
        {
            panel.Children.Add(new SettingsRenderer(_session, _terminal, _owner, _selectedPageID, _refresh).Render());
        }

        var actions = new ActionRenderer(_session, _terminal, _owner, _refresh);
        var controls = new ControlRenderer(_session, _owner, SaveAndRefreshAsync, actions);
        foreach (var section in page.Sections)
        {
            panel.Children.Add(RenderSection(section, controls, actions));
        }

        return panel;
    }

    private Control Header(BundlePage page)
    {
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(new TextBlock
        {
            Text = $"{IconText.For(page, _session.IconMap)} {page.Title}",
            FontSize = 24,
            FontWeight = FontWeight.SemiBold,
            TextWrapping = TextWrapping.Wrap,
        });
        if (!string.IsNullOrWhiteSpace(page.Summary))
        {
            panel.Children.Add(new TextBlock { Text = page.Summary, Opacity = 0.74, TextWrapping = TextWrapping.Wrap });
        }
        AutomationProperties.SetName(panel, page.Title);
        return panel;
    }

    private Control RenderSection(PageSection section, ControlRenderer controls, ActionRenderer actions)
    {
        var card = new Border
        {
            CornerRadius = new CornerRadius(10),
            BorderThickness = new Thickness(1),
            BorderBrush = Brushes.Gray,
            Padding = new Thickness(16),
            Margin = new Thickness(0, 0, 0, 10),
        };
        var panel = new StackPanel { Spacing = 10 };
        panel.Children.Add(new TextBlock
        {
            Text = $"{IconText.For(section, _session.IconMap)} {section.Title ?? section.Id}",
            FontSize = 18,
            FontWeight = FontWeight.SemiBold,
            TextWrapping = TextWrapping.Wrap,
        });
        var summary = section.Summary ?? section.Subtitle;
        if (!string.IsNullOrWhiteSpace(summary))
        {
            panel.Children.Add(new TextBlock { Text = summary, Opacity = 0.74, TextWrapping = TextWrapping.Wrap });
        }

        var sectionValues = _session.SectionContextValues(section.Id);
        var sectionContext = _session.CommandContext(sectionValues);
        foreach (var control in section.Controls)
        {
            panel.Children.Add(controls.Render(control, sectionContext));
        }

        if (section.Actions.Count > 0)
        {
            var actionPanel = new WrapPanel { Orientation = Orientation.Horizontal };
            foreach (var action in section.Actions.Where(action => RenderingEngine.IsActionVisible(action, sectionContext)))
            {
                var button = actions.Render(action, sectionContext);
                button.Margin = new Thickness(0, 0, 8, 6);
                actionPanel.Children.Add(button);
            }
            panel.Children.Add(actionPanel);
        }

        card.Child = panel;
        AutomationProperties.SetName(card, section.Title ?? section.Id);
        return card;
    }

    private async Task SaveAndRefreshAsync()
    {
        await _session.SaveStateAsync(_selectedPageID);
        await _refresh();
    }
}
