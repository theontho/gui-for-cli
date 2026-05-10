using GUIForCLIWindows;
using GUIForCLIWindows.Core;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace GUIForCLIWindows.Pages;

public sealed partial class HomePage : Page
{
    private readonly SimpleProcessRunner _processRunner = new();
    private BundleManifest? _manifest;
    private string _bundleRoot = "";
    private string _bundleWorkspace = "";
    private Dictionary<string, string> _fieldValues = [];
    private Dictionary<string, string> _configValues = [];
    private Dictionary<string, IReadOnlyList<string>> _checkedOptions = [];
    private Dictionary<string, string> _configFilePaths = [];
    private string? _requestedPageID;
    private bool _showedStartupMessages;

    public HomePage()
    {
        InitializeComponent();
        NavigationCacheMode = NavigationCacheMode.Required;
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is BundlePageNavigationParameter parameter)
        {
            LoadSession(parameter.Session, parameter.PageID);
            return;
        }

        BundleInfoBar.Severity = InfoBarSeverity.Error;
        BundleInfoBar.Title = "Could not load bundle";
        BundleInfoBar.Message = "No preloaded bundle session was provided.";
    }

    private void LoadSession(AppBundleSession session, string? requestedPageID)
    {
        _manifest = session.Manifest;
        _bundleRoot = session.BundleRoot;
        _bundleWorkspace = session.BundleWorkspace;
        _fieldValues = session.FieldValues;
        _configValues = session.ConfigValues;
        _checkedOptions = session.CheckedOptions;
        _configFilePaths = session.ConfigFilePaths;
        _requestedPageID = requestedPageID;

        BundleTitle.Text = _manifest.DisplayName;
        BundleSummary.Text = _manifest.Summary;
        AutomationProperties.SetAutomationId(SaveStateButton, "SaveStateButton");
        AutomationProperties.SetName(SaveStateButton, "Save bundle state");
        BundleInfoBar.Title = "Bundle loaded";
        BundleInfoBar.Message = $"{_manifest.Pages.Count} pages and {RenderingEngine.AllControls(_manifest).Count} controls preloaded from Examples\\WGSExtract.";
        BundleInfoBar.Severity = InfoBarSeverity.Success;
        if (!_showedStartupMessages)
        {
            foreach (var message in session.StartupMessages)
            {
                AppendOutput(message);
            }

            _showedStartupMessages = true;
        }

        RenderSelectedPage();
    }

    private async void SaveState_Click(object sender, RoutedEventArgs e)
    {
        if (_manifest is null)
        {
            return;
        }

        await SaveStateAsync();
        BundleInfoBar.Severity = InfoBarSeverity.Success;
        BundleInfoBar.Title = "State saved";
        BundleInfoBar.Message = $"Saved fields and options to {_bundleWorkspace}.";
    }

    private async Task SaveStateAsync()
    {
        await BundleStateStore.SaveBundleStateAsync(_bundleWorkspace, new BundleState
        {
            FieldValues = new Dictionary<string, string>(_fieldValues),
            CheckedOptions = _checkedOptions.ToDictionary(pair => pair.Key, pair => pair.Value.ToList()),
            ConfigFilePaths = new Dictionary<string, string>(_configFilePaths),
        });
    }

    private void RenderSelectedPage()
    {
        PageContent.Children.Clear();
        if (_manifest is null)
        {
            return;
        }

        var page = _manifest.Pages.FirstOrDefault(candidate => string.Equals(candidate.Id, _requestedPageID, StringComparison.Ordinal))
            ?? _manifest.Pages.FirstOrDefault(candidate => !string.Equals(candidate.Id, "settings", StringComparison.Ordinal))
            ?? _manifest.Pages.FirstOrDefault();
        if (page is null)
        {
            return;
        }

        var pageHeader = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        pageHeader.Children.Add(new FontIcon
        {
            Glyph = WindowsIconMapper.GlyphFor(page.IconName),
            FontSize = 18,
        });
        pageHeader.Children.Add(new TextBlock
        {
            Text = page.Title,
            Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"],
        });
        AutomationProperties.SetAutomationId(pageHeader, $"PageHeader_{page.Id}");
        AutomationProperties.SetName(pageHeader, page.Title);
        PageContent.Children.Add(pageHeader);
        if (!string.IsNullOrWhiteSpace(page.Summary))
        {
            PageContent.Children.Add(new TextBlock
            {
                Text = page.Summary,
                TextWrapping = TextWrapping.Wrap,
                MaxWidth = 860,
            });
        }

        foreach (var section in page.Sections)
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

    private Button RenderActionButton(ActionSpec action)
    {
        var button = new Button
        {
            Content = action.Title,
            Tag = action,
            Style = action.Destructive ? (Style)Application.Current.Resources["AccentButtonStyle"] : null,
        };
        AutomationProperties.SetAutomationId(button, $"Action_{action.Id}");
        AutomationProperties.SetName(button, action.Title);
        button.Click += async (_, _) => await RunActionAsync(action);
        ApplyActionState(button, action);
        return button;
    }

    private async Task RunActionAsync(ActionSpec action)
    {
        if (!await ConfirmActionAsync(action))
        {
            AppendOutput($"Cancelled {action.Title}.");
            return;
        }

        var context = RenderContext();
        var missing = RenderingEngine.MissingPlaceholders(action.Command, context);
        if (missing.Count > 0)
        {
            AppendOutput($"Cannot run {action.Title}. Missing: {string.Join(", ", missing)}");
            return;
        }

        var command = RenderingEngine.RenderedCommand(action.Command, context);
        AppendOutput($"> {RenderingEngine.DisplayCommand(action.Command, context)}");
        try
        {
            var result = await _processRunner.RunAsync(new ProcessExecutionRequest
            {
                Command = command,
                WorkingDirectory = _bundleRoot,
                Timeout = TimeSpan.FromMinutes(10),
                Environment = new Dictionary<string, string>
                {
                    ["GUI_FOR_CLI_BUNDLE_ROOT"] = _bundleRoot,
                    ["GUI_FOR_CLI_BUNDLE_WORKSPACE"] = _bundleWorkspace,
                },
            });
            AppendOutput(result.StandardOutput);
            AppendOutput(result.StandardError);
            AppendOutput($"Exit code: {result.ExitCode}");
        }
        catch (Exception error)
        {
            AppendOutput($"Action failed: {error.Message}");
        }
    }

    private async Task<bool> ConfirmActionAsync(ActionSpec action)
    {
        if (action.Confirm is not { } confirm)
        {
            return true;
        }

        TextBox? promptBox = null;
        var panel = new StackPanel { Spacing = 12 };
        if (!string.IsNullOrWhiteSpace(confirm.Message))
        {
            panel.Children.Add(new TextBlock
            {
                Text = confirm.Message,
                TextWrapping = TextWrapping.Wrap,
            });
        }

        if (!string.IsNullOrWhiteSpace(confirm.RequiredText))
        {
            promptBox = new TextBox
            {
                Header = string.IsNullOrWhiteSpace(confirm.Prompt) ? $"Type {confirm.RequiredText} to continue" : confirm.Prompt,
                PlaceholderText = confirm.RequiredText,
            };
            AutomationProperties.SetAutomationId(promptBox, $"ConfirmPrompt_{action.Id}");
            AutomationProperties.SetName(promptBox, promptBox.Header?.ToString() ?? "Confirmation prompt");
            panel.Children.Add(promptBox);
        }

        var dialog = new ContentDialog
        {
            Title = string.IsNullOrWhiteSpace(confirm.Title) ? action.Title : confirm.Title,
            Content = panel,
            PrimaryButtonText = string.IsNullOrWhiteSpace(confirm.ConfirmButtonTitle) ? "Continue" : confirm.ConfirmButtonTitle,
            CloseButtonText = string.IsNullOrWhiteSpace(confirm.CancelButtonTitle) ? "Cancel" : confirm.CancelButtonTitle,
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = XamlRoot,
        };

        var result = await dialog.ShowAsync();
        return result == ContentDialogResult.Primary
            && (promptBox is null || string.Equals(promptBox.Text, confirm.RequiredText, StringComparison.Ordinal));
    }

    private void UpdateCheckedOption(string controlID, string optionID, bool isSelected)
    {
        var selected = _checkedOptions.TryGetValue(controlID, out var values) ? values.ToHashSet(StringComparer.Ordinal) : [];
        if (isSelected)
        {
            selected.Add(optionID);
        }
        else
        {
            selected.Remove(optionID);
        }

        _checkedOptions[controlID] = selected.Order(StringComparer.Ordinal).ToList();
        RefreshActionButtons();
    }

    private void RefreshActionButtons()
    {
        foreach (var button in Descendants<Button>(PageContent).Where(button => button.Tag is ActionSpec))
        {
            ApplyActionState(button, (ActionSpec)button.Tag);
        }
    }

    private void ApplyActionState(Button button, ActionSpec action)
    {
        var context = RenderContext();
        var missing = RenderingEngine.MissingPlaceholders(action.Command, context);
        var disabledReason = RenderingEngine.DisabledReason(action, context);
        button.IsEnabled = RenderingEngine.IsActionVisible(action, context) && missing.Count == 0 && disabledReason is null;
        ToolTipService.SetToolTip(button, missing.Count > 0 ? $"Missing: {string.Join(", ", missing)}" : disabledReason ?? action.Tooltip);
    }

    private RenderContext RenderContext() => new()
    {
        BundleRootPath = _bundleRoot,
        HomePath = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        FieldValues = _fieldValues,
        ConfigValues = _configValues,
        CheckedOptions = RenderingEngine.CheckedOptionsForContext(_checkedOptions.ToDictionary(pair => pair.Key, pair => (IReadOnlyCollection<string>)pair.Value)),
    };

    private void AppendOutput(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        OutputBox.Text += $"{text.TrimEnd()}{Environment.NewLine}";
        OutputBox.SelectionStart = OutputBox.Text.Length;
    }

    private static IEnumerable<T> Descendants<T>(DependencyObject root)
        where T : DependencyObject
    {
        var count = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(root);
        for (var index = 0; index < count; index += 1)
        {
            var child = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(root, index);
            if (child is T typed)
            {
                yield return typed;
            }

            foreach (var descendant in Descendants<T>(child))
            {
                yield return descendant;
            }
        }
    }

}
