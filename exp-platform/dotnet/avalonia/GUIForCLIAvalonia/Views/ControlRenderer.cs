using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using GUIForCLIAvalonia.Services;
using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Views;

public sealed class ControlRenderer
{
    private readonly DesktopBundleSession _session;
    private readonly Window _owner;
    private readonly Func<Task> _saveAndRefresh;
    private readonly ActionRenderer _actions;

    public ControlRenderer(DesktopBundleSession session, Window owner, Func<Task> saveAndRefresh, ActionRenderer actions)
    {
        _session = session;
        _owner = owner;
        _saveAndRefresh = saveAndRefresh;
        _actions = actions;
    }

    public Control Render(ControlSpec control, RenderContext sectionContext)
    {
        var panel = new StackPanel { Spacing = 5, Margin = new Thickness(0, 0, 0, 10) };
        panel.Children.Add(new TextBlock { Text = control.Label, FontWeight = FontWeight.SemiBold });
        if (!string.IsNullOrWhiteSpace(control.Tooltip))
        {
            panel.Children.Add(new TextBlock { Text = control.Tooltip, Opacity = 0.74, TextWrapping = TextWrapping.Wrap });
        }

        panel.Children.Add(control.Kind switch
        {
            "text" => TextField(control),
            "path" => PathField(control),
            "dropdown" => Dropdown(control),
            "toggle" => Toggle(control),
            "checkboxGroup" => CheckboxGroup(control),
            "infoGrid" => InfoGrid(control),
            "libraryList" => LibraryList(control, sectionContext),
            "configEditor" => ConfigEditor(control),
            _ => new TextBlock { Text = $"Unsupported control kind: {control.Kind}" },
        });
        AutomationProperties.SetName(panel, control.Label);
        return panel;
    }

    private Control TextField(ControlSpec control)
    {
        var box = new TextBox { Text = FieldValue(control), Watermark = control.Placeholder ?? "" };
        AutomationProperties.SetName(box, control.Label);
        box.TextChanged += async (_, _) =>
        {
            _session.FieldValues[control.Id] = box.Text ?? "";
            await _saveAndRefresh();
        };
        return box;
    }

    private Control PathField(ControlSpec control)
    {
        var box = new TextBox { Text = FieldValue(control), Watermark = control.Placeholder ?? "", FlowDirection = FlowDirection.LeftToRight };
        AutomationProperties.SetName(box, control.Label);
        box.TextChanged += async (_, _) =>
        {
            _session.FieldValues[control.Id] = box.Text ?? "";
            await _session.SaveStateAsync(_session.BundleState.SelectedPageID);
        };
        return PathRow(box, control.Id, control.Label, control.Placeholder, control.Tooltip);
    }

    private Control Dropdown(ControlSpec control)
    {
        var combo = new ComboBox { MinWidth = 260 };
        var items = control.Options.Select(option => new ComboBoxItem { Content = option.Title, Tag = option.Id }).ToList();
        combo.ItemsSource = items;

        SelectCombo(combo, FieldValue(control), items);
        combo.SelectionChanged += async (_, _) =>
        {
            if (combo.SelectedItem is ComboBoxItem item)
            {
                _session.FieldValues[control.Id] = item.Tag?.ToString() ?? "";
                await _saveAndRefresh();
            }
        };
        AutomationProperties.SetName(combo, control.Label);
        return combo;
    }

    private Control Toggle(ControlSpec control)
    {
        var check = new CheckBox { Content = control.Label, IsChecked = string.Equals(FieldValue(control), "true", StringComparison.OrdinalIgnoreCase) };
        check.Checked += async (_, _) => await SetToggle(control.Id, true);
        check.Unchecked += async (_, _) => await SetToggle(control.Id, false);
        AutomationProperties.SetName(check, control.Label);
        return check;
    }

    private Control CheckboxGroup(ControlSpec control)
    {
        var selected = _session.CheckedOptions.TryGetValue(control.Id, out var values) ? values.ToHashSet(StringComparer.Ordinal) : [];
        var panel = new WrapPanel { Orientation = Orientation.Horizontal };
        foreach (var option in control.Options)
        {
            var check = new CheckBox { Content = option.Title, IsChecked = selected.Contains(option.Id), Margin = new Thickness(0, 0, 14, 6) };
            check.Checked += async (_, _) => await SetChecked(control.Id, option.Id, true);
            check.Unchecked += async (_, _) => await SetChecked(control.Id, option.Id, false);
            AutomationProperties.SetName(check, $"{control.Label}: {option.Title}");
            panel.Children.Add(check);
        }

        return panel;
    }

    private Control InfoGrid(ControlSpec control)
    {
        var panel = new StackPanel { Spacing = 4 };
        foreach (var row in RenderingEngine.HydrateRows(control))
        {
            panel.Children.Add(new TextBlock { Text = $"{row.Title ?? row.Id}: {string.Join(", ", row.Values.Select(pair => $"{pair.Key}={pair.Value}"))}" });
        }

        return panel;
    }

    private Control LibraryList(ControlSpec control, RenderContext sectionContext)
    {
        var panel = new StackPanel { Spacing = 8 };
        var rows = RenderingEngine.HydrateRows(control);
        if (rows.Count == 0)
        {
            panel.Children.Add(new TextBlock { Text = "No rows available.", Opacity = 0.74 });
            return panel;
        }

        foreach (var row in rows)
        {
            panel.Children.Add(new LibraryRowRenderer(_actions, sectionContext).Render(control, row));
        }

        return panel;
    }

    private Control ConfigEditor(ControlSpec control)
    {
        var panel = new StackPanel { Spacing = 8 };
        if (control.ConfigFile is not null)
        {
            var path = _session.ConfigFilePaths.TryGetValue(control.Id, out var saved) ? saved : control.ConfigFile.Path;
            var box = new TextBox { Text = path, FlowDirection = FlowDirection.LeftToRight };
            box.TextChanged += async (_, _) =>
            {
                _session.ConfigFilePaths[control.Id] = box.Text ?? "";
                await _session.SaveStateAsync(_session.BundleState.SelectedPageID);
            };
            panel.Children.Add(PathRow(box, control.Id, "Settings file", null, null));
        }

        foreach (var setting in control.Settings)
        {
            panel.Children.Add(ConfigSetting(control, setting));
        }

        return panel;
    }

    private Control ConfigSetting(ControlSpec control, ConfigSettingSpec setting)
    {
        var label = string.IsNullOrWhiteSpace(setting.Label) ? setting.Id : setting.Label;
        var key = RenderingEngine.ConfigValueKey(control, setting);
        if (setting.Kind == "dropdown" && setting.Options.Count > 0)
        {
            var combo = new ComboBox { MinWidth = 260 };
            var items = setting.Options.Select(option => new ComboBoxItem { Content = option.Title, Tag = option.Id }).ToList();
            combo.ItemsSource = items;
            SelectCombo(combo, ConfigValue(key, setting), items);
            combo.SelectionChanged += async (_, _) =>
            {
                if (combo.SelectedItem is ComboBoxItem item)
                {
                    await SaveConfigValue(control, setting, item.Tag?.ToString() ?? "");
                }
            };
            return Labeled(label, combo, setting.Tooltip);
        }

        var box = new TextBox { Text = ConfigValue(key, setting), Watermark = setting.Placeholder ?? "", FlowDirection = setting.Kind == "path" ? FlowDirection.LeftToRight : FlowDirection.LeftToRight };
        box.TextChanged += async (_, _) => await SaveConfigValue(control, setting, box.Text ?? "");
        var input = setting.Kind == "path" ? PathRow(box, setting.Id, label, setting.Placeholder, setting.Tooltip) : box;
        return Labeled(label, input, setting.Tooltip);
    }

    private Control PathRow(TextBox box, string id, string label, string? placeholder, string? tooltip)
    {
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto"), ColumnSpacing = 8 };
        Grid.SetColumn(box, 0);
        row.Children.Add(box);
        var button = new Button { Content = "Choose...", VerticalAlignment = VerticalAlignment.Bottom };
        button.Click += async (_, _) =>
        {
            if (TopLevel.GetTopLevel(_owner) is { } topLevel)
            {
                var selected = await PathPickerService.PickAsync(topLevel, label, box.Text ?? "", PathPickerService.LooksLikeFolder(id, label, placeholder, tooltip));
                if (!string.IsNullOrWhiteSpace(selected))
                {
                    box.Text = selected;
                }
            }
        };
        Grid.SetColumn(button, 1);
        row.Children.Add(button);
        return row;
    }

    private static Control Labeled(string label, Control input, string? tooltip)
    {
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(new TextBlock { Text = label, FontWeight = FontWeight.SemiBold });
        if (!string.IsNullOrWhiteSpace(tooltip))
        {
            panel.Children.Add(new TextBlock { Text = tooltip, Opacity = 0.74, TextWrapping = TextWrapping.Wrap });
        }
        panel.Children.Add(input);
        return panel;
    }

    private string FieldValue(ControlSpec control) =>
        _session.FieldValues.TryGetValue(control.Id, out var value) ? value : control.Value ?? "";

    private string ConfigValue(string key, ConfigSettingSpec setting) =>
        _session.ConfigValues.TryGetValue(key, out var value) ? value : setting.Value ?? "";

    private async Task SaveConfigValue(ControlSpec control, ConfigSettingSpec setting, string value)
    {
        var key = RenderingEngine.ConfigValueKey(control, setting);
        _session.ConfigValues[key] = value;
        if (_session.FieldValues.ContainsKey(setting.Id))
        {
            _session.FieldValues[setting.Id] = value;
        }
        await _session.SaveConfigEditorAsync(control);
        if (setting.Kind == "path")
        {
            await _saveAndRefresh();
        }
    }

    private async Task SetToggle(string id, bool value)
    {
        _session.FieldValues[id] = value ? "true" : "false";
        await _saveAndRefresh();
    }

    private async Task SetChecked(string controlID, string optionID, bool isSelected)
    {
        var selected = _session.CheckedOptions.TryGetValue(controlID, out var values) ? values.ToHashSet(StringComparer.Ordinal) : [];
        if (isSelected) selected.Add(optionID); else selected.Remove(optionID);
        _session.CheckedOptions[controlID] = selected.Order(StringComparer.Ordinal).ToList();
        await _saveAndRefresh();
    }

    private static void SelectCombo(ComboBox combo, string value, IReadOnlyList<ComboBoxItem> items)
    {
        combo.SelectedItem = items.FirstOrDefault(item => string.Equals(item.Tag?.ToString(), value, StringComparison.Ordinal));
        combo.SelectedIndex = combo.SelectedIndex < 0 && items.Count > 0 ? 0 : combo.SelectedIndex;
    }
}
