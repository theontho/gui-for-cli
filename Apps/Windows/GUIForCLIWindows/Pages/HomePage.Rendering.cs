using GUIForCLIWindows.Core;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GUIForCLIWindows.Pages;

public sealed partial class HomePage
{
    private void RenderSelectedPage()
    {
        PageContent.Children.Clear();
        if (PageSelector.SelectedItem is not PageChoice choice)
        {
            return;
        }

        var pageHeader = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        pageHeader.Children.Add(new FontIcon
        {
            Glyph = WindowsIconMapper.GlyphFor(choice.Page.IconName),
            FontSize = 18,
        });
        pageHeader.Children.Add(new TextBlock
        {
            Text = choice.Page.Title,
            Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"],
        });
        AutomationProperties.SetAutomationId(pageHeader, $"PageHeader_{choice.Page.Id}");
        AutomationProperties.SetName(pageHeader, choice.Page.Title);
        PageContent.Children.Add(pageHeader);
        if (!string.IsNullOrWhiteSpace(choice.Page.Summary))
        {
            PageContent.Children.Add(new TextBlock
            {
                Text = choice.Page.Summary,
                TextWrapping = TextWrapping.Wrap,
                MaxWidth = 860,
            });
        }

        foreach (var section in choice.Page.Sections)
        {
            PageContent.Children.Add(RenderSection(section));
        }
    }

    private FrameworkElement RenderSection(PageSection section)
    {
        var panel = new StackPanel { Spacing = 12, Padding = new Thickness(16) };
        AutomationProperties.SetAutomationId(panel, $"Section_{section.Id}");
        AutomationProperties.SetName(panel, section.Title ?? section.Id);
        var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        header.Children.Add(new FontIcon
        {
            Glyph = WindowsIconMapper.GlyphFor(section.IconName),
            FontSize = 16,
        });
        header.Children.Add(new TextBlock
        {
            Text = section.Title ?? section.Id,
            Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"],
        });
        panel.Children.Add(header);
        if (!string.IsNullOrWhiteSpace(section.Subtitle))
        {
            panel.Children.Add(new TextBlock { Text = section.Subtitle, TextWrapping = TextWrapping.Wrap });
        }

        foreach (var control in section.Controls)
        {
            panel.Children.Add(RenderControl(control));
        }

        if (section.Actions.Count > 0)
        {
            var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            foreach (var action in section.Actions)
            {
                actions.Children.Add(RenderActionButton(action));
            }

            panel.Children.Add(actions);
        }

        var border = new Border
        {
            Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Child = panel,
        };
        AutomationProperties.SetAutomationId(border, $"SectionCard_{section.Id}");
        AutomationProperties.SetName(border, section.Title ?? section.Id);
        return border;
    }

    private FrameworkElement RenderControl(ControlSpec control)
    {
        var container = new StackPanel { Spacing = 4 };
        AutomationProperties.SetAutomationId(container, $"Control_{control.Id}");
        AutomationProperties.SetName(container, control.Label);
        container.Children.Add(new TextBlock { Text = control.Label, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        if (!string.IsNullOrWhiteSpace(control.Tooltip))
        {
            container.Children.Add(new TextBlock { Text = control.Tooltip, Opacity = 0.72, TextWrapping = TextWrapping.Wrap });
        }

        container.Children.Add(control.Kind switch
        {
            "text" or "path" => RenderTextControl(control),
            "dropdown" => RenderDropdown(control),
            "toggle" => RenderToggle(control),
            "checkboxGroup" => RenderCheckboxGroup(control),
            "infoGrid" => RenderInfoGrid(control),
            "libraryList" => RenderLibraryList(control),
            "configEditor" => RenderConfigEditor(control),
            _ => new TextBlock { Text = $"Unsupported control kind: {control.Kind}" },
        });
        return container;
    }

    private FrameworkElement RenderTextControl(ControlSpec control)
    {
        var box = new TextBox
        {
            Text = _fieldValues.TryGetValue(control.Id, out var value) ? value : "",
            PlaceholderText = control.Placeholder ?? "",
        };
        AutomationProperties.SetName(box, control.Label);
        AutomationProperties.SetAutomationId(box, $"Field_{control.Id}");
        box.TextChanged += (_, _) =>
        {
            _fieldValues[control.Id] = box.Text;
            RefreshActionButtons();
        };
        return box;
    }

    private FrameworkElement RenderDropdown(ControlSpec control)
    {
        var combo = new ComboBox
        {
            ItemsSource = control.Options,
            DisplayMemberPath = nameof(ControlOption.Title),
            MinWidth = 240,
        };
        AutomationProperties.SetName(combo, control.Label);
        AutomationProperties.SetAutomationId(combo, $"Field_{control.Id}");
        var value = _fieldValues.TryGetValue(control.Id, out var selected) ? selected : control.Value;
        combo.SelectedItem = control.Options.FirstOrDefault(option => option.Id == value) ?? control.Options.FirstOrDefault(option => option.Selected);
        if (combo.SelectedItem is ControlOption selectedOption)
        {
            _fieldValues[control.Id] = selectedOption.Id;
        }

        combo.SelectionChanged += (_, _) =>
        {
            if (combo.SelectedItem is ControlOption option)
            {
                _fieldValues[control.Id] = option.Id;
                RefreshActionButtons();
            }
        };
        return combo;
    }

    private FrameworkElement RenderToggle(ControlSpec control)
    {
        var toggle = new ToggleSwitch
        {
            IsOn = string.Equals(_fieldValues.TryGetValue(control.Id, out var value) ? value : control.Value, "true", StringComparison.OrdinalIgnoreCase),
        };
        AutomationProperties.SetName(toggle, control.Label);
        AutomationProperties.SetAutomationId(toggle, $"Field_{control.Id}");
        toggle.Toggled += (_, _) =>
        {
            _fieldValues[control.Id] = toggle.IsOn ? "true" : "false";
            RefreshActionButtons();
        };
        return toggle;
    }

    private FrameworkElement RenderCheckboxGroup(ControlSpec control)
    {
        var selected = _checkedOptions.TryGetValue(control.Id, out var values) ? values.ToHashSet(StringComparer.Ordinal) : [];
        var panel = new StackPanel { Spacing = 4 };
        foreach (var option in control.Options)
        {
            var checkBox = new CheckBox
            {
                Content = option.Title,
                IsChecked = selected.Contains(option.Id),
            };
            AutomationProperties.SetName(checkBox, $"{control.Label}: {option.Title}");
            AutomationProperties.SetAutomationId(checkBox, $"Field_{control.Id}_{option.Id}");
            checkBox.Checked += (_, _) => UpdateCheckedOption(control.Id, option.Id, true);
            checkBox.Unchecked += (_, _) => UpdateCheckedOption(control.Id, option.Id, false);
            panel.Children.Add(checkBox);
        }

        return panel;
    }

    private FrameworkElement RenderInfoGrid(ControlSpec control)
    {
        var rows = RenderingEngine.HydrateRows(control);
        var panel = new StackPanel { Spacing = 4 };
        foreach (var row in rows)
        {
            panel.Children.Add(new TextBlock { Text = $"{row.Title ?? row.Id}: {string.Join(", ", row.Values.Select(pair => $"{pair.Key}={pair.Value}"))}" });
        }

        return panel;
    }

    private FrameworkElement RenderLibraryList(ControlSpec control)
    {
        var list = new ListView { MaxHeight = 260 };
        AutomationProperties.SetName(list, control.Label);
        AutomationProperties.SetAutomationId(list, $"Field_{control.Id}");
        list.ItemsSource = RenderingEngine.HydrateRows(control)
            .Select(row => $"{row.Title ?? row.Id}  {row.Status ?? ""}  {string.Join("  ", row.Tags.Select(tag => tag.Title))}")
            .ToList();
        return list;
    }

    private FrameworkElement RenderConfigEditor(ControlSpec control)
    {
        var panel = new StackPanel { Spacing = 8 };
        AutomationProperties.SetAutomationId(panel, $"ConfigEditor_{control.Id}");
        AutomationProperties.SetName(panel, control.Label);
        if (control.ConfigFile is not null)
        {
            var pathBox = new TextBox
            {
                Header = "Settings file",
                Text = _configFilePaths.TryGetValue(control.Id, out var path) ? path : control.ConfigFile.Path,
            };
            AutomationProperties.SetAutomationId(pathBox, $"ConfigPath_{control.Id}");
            AutomationProperties.SetName(pathBox, $"{control.Label} settings file");
            pathBox.TextChanged += (_, _) => _configFilePaths[control.Id] = pathBox.Text;
            panel.Children.Add(pathBox);
        }

        foreach (var setting in control.Settings)
        {
            var key = RenderingEngine.ConfigValueKey(control, setting);
            var box = new TextBox
            {
                Header = string.IsNullOrWhiteSpace(setting.Label) ? setting.Id : setting.Label,
                Text = _configValues.TryGetValue(key, out var value) ? value : setting.Value ?? "",
                PlaceholderText = setting.Placeholder ?? "",
            };
            AutomationProperties.SetAutomationId(box, $"Config_{control.Id}_{setting.Id}");
            AutomationProperties.SetName(box, string.IsNullOrWhiteSpace(setting.Label) ? setting.Id : setting.Label);
            box.TextChanged += (_, _) =>
            {
                _configValues[key] = box.Text;
                if (_fieldValues.ContainsKey(setting.Id))
                {
                    _fieldValues[setting.Id] = box.Text;
                }
            };
            panel.Children.Add(box);
        }

        return panel;
    }

}
