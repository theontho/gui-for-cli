using GUIForCLIWindows;
using GUIForCLIWindows.Core;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace GUIForCLIWindows.Pages;

public sealed partial class HomePage : Page
{
    private readonly SimpleProcessRunner _processRunner = new();
    private AppBundleSession? _session;
    private BundleManifest? _manifest;
    private string _bundleRoot = "";
    private string _bundleWorkspace = "";
    private Dictionary<string, string> _fieldValues = [];
    private Dictionary<string, string> _configValues = [];
    private Dictionary<string, IReadOnlyList<string>> _checkedOptions = [];
    private Dictionary<string, string> _configFilePaths = [];
    private string? _requestedPageID;
    private BundleSetupRunState? _setupRun;
    private bool _showedStartupMessages;
    private bool _isResizingOutput;
    private double _outputResizeStartY;
    private double _outputResizeStartHeight;

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

        AppendOutput("Could not load bundle: no preloaded bundle session was provided.");
    }

    private void LoadSession(AppBundleSession session, string? requestedPageID)
    {
        _session = session;
        _manifest = session.Manifest;
        _bundleRoot = session.BundleRoot;
        _bundleWorkspace = session.BundleWorkspace;
        _fieldValues = session.FieldValues;
        _configValues = session.ConfigValues;
        _checkedOptions = session.CheckedOptions;
        _configFilePaths = session.ConfigFilePaths;
        _requestedPageID = requestedPageID;
        _setupRun = session.BundleState.SetupRun;

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

    private async Task SaveStateAsync()
    {
        if (_session is null)
        {
            return;
        }

        await _session.SaveStateAsync(_requestedPageID, _setupRun);
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

        if (string.Equals(page.Id, "settings", StringComparison.Ordinal))
        {
            PageContent.Children.Add(RenderAppearanceSettingsSection());
            PageContent.Children.Add(RenderSetupStatusSection());
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
            "text" => RenderTextControl(control),
            "path" => RenderPathControl(control),
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
            _ = SaveStateAsync();
        };
        return box;
    }

    private FrameworkElement RenderPathControl(ControlSpec control)
    {
        var box = CreateTextBox(
            _fieldValues.TryGetValue(control.Id, out var value) ? value : "",
            control.Placeholder,
            $"Field_{control.Id}",
            control.Label);
        box.TextChanged += (_, _) =>
        {
            _fieldValues[control.Id] = box.Text;
            RefreshActionButtons();
            _ = SaveStateAsync();
        };

        return RenderPathPickerRow(
            box,
            PickerTargetFor(control.Id, control.Label, control.Placeholder),
            control.Label);
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
                _ = SaveStateAsync();
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
            _ = SaveStateAsync();
        };
        return toggle;
    }

    private FrameworkElement RenderCheckboxGroup(ControlSpec control)
    {
        var selected = _checkedOptions.TryGetValue(control.Id, out var values) ? values.ToHashSet(StringComparer.Ordinal) : [];
        var panel = new StackPanel { Spacing = 8 };
        string? previousGroup = null;
        Grid? optionGrid = null;
        var optionIndex = 0;
        foreach (var option in control.Options)
        {
            if (!string.IsNullOrWhiteSpace(option.Group)
                && !string.Equals(option.Group, previousGroup, StringComparison.Ordinal))
            {
                panel.Children.Add(new TextBlock
                {
                    Text = option.Group,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                    Margin = new Thickness(0, previousGroup is null ? 0 : 8, 0, 0),
                });
                previousGroup = option.Group;
                optionGrid = CreateCheckboxGrid();
                panel.Children.Add(optionGrid);
                optionIndex = 0;
            }
            else if (optionGrid is null)
            {
                optionGrid = CreateCheckboxGrid();
                panel.Children.Add(optionGrid);
            }

            var checkBox = new CheckBox
            {
                Content = option.Title,
                IsChecked = selected.Contains(option.Id),
            };
            AutomationProperties.SetName(checkBox, $"{control.Label}: {option.Title}");
            AutomationProperties.SetAutomationId(checkBox, $"Field_{control.Id}_{option.Id}");
            checkBox.Checked += (_, _) =>
            {
                UpdateCheckedOption(control.Id, option.Id, true);
                _ = SaveStateAsync();
            };
            checkBox.Unchecked += (_, _) =>
            {
                UpdateCheckedOption(control.Id, option.Id, false);
                _ = SaveStateAsync();
            };
            AddCheckboxToGrid(optionGrid, checkBox, optionIndex);
            optionIndex += 1;
        }

        return panel;
    }

    private static Grid CreateCheckboxGrid()
    {
        var grid = new Grid
        {
            ColumnSpacing = 16,
            RowSpacing = 4,
        };
        for (var column = 0; column < 3; column += 1)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        }

        return grid;
    }

    private static void AddCheckboxToGrid(Grid grid, CheckBox checkBox, int optionIndex)
    {
        const int columns = 3;
        var row = optionIndex / columns;
        while (grid.RowDefinitions.Count <= row)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        }

        Grid.SetRow(checkBox, row);
        Grid.SetColumn(checkBox, optionIndex % columns);
        grid.Children.Add(checkBox);
    }

    private FrameworkElement RenderAppearanceSettingsSection()
    {
        var panel = new StackPanel { Spacing = 12, Padding = new Thickness(16) };
        AutomationProperties.SetAutomationId(panel, "AppearanceSettingsSection");
        AutomationProperties.SetName(panel, "Appearance settings");
        panel.Children.Add(new TextBlock
        {
            Text = "Appearance",
            Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"],
        });

        var language = new ComboBox
        {
            Header = "Language",
            MinWidth = 260,
        };
        language.Items.Add(new ComboBoxItem { Content = "Use system default", Tag = "" });
        foreach (var option in _session?.LocaleOptions ?? [])
        {
            language.Items.Add(new ComboBoxItem { Content = option.Name, Tag = option.Code });
        }

        var localeCode = _session?.BundleState.LocalizationCode ?? "";
        language.SelectedItem = language.Items
            .OfType<ComboBoxItem>()
            .FirstOrDefault(item => string.Equals(item.Tag?.ToString(), localeCode, StringComparison.Ordinal))
            ?? language.Items[0];
        ToolTipService.SetToolTip(language, "Choose the interface language for this bundle.");
        language.SelectionChanged += async (_, _) =>
        {
            if (language.SelectedItem is ComboBoxItem item && _session is not null)
            {
                await _session.SavePreferencesAsync(item.Tag?.ToString(), _session.BundleState.ColorTheme);
                if (Application.Current is App app && app.MainWindow is { } mainWindow)
                {
                    await mainWindow.ReloadBundleAsync();
                }
            }
        };
        panel.Children.Add(language);

        var theme = new ComboBox
        {
            Header = "Theme",
            MinWidth = 260,
        };
        theme.Items.Add(new ComboBoxItem { Content = "System", Tag = "system" });
        theme.Items.Add(new ComboBoxItem { Content = "Light", Tag = "light" });
        theme.Items.Add(new ComboBoxItem { Content = "Dark", Tag = "dark" });
        theme.SelectedItem = theme.Items
            .OfType<ComboBoxItem>()
            .FirstOrDefault(item => string.Equals(item.Tag?.ToString(), _session?.BundleState.ColorTheme, StringComparison.Ordinal))
            ?? theme.Items[0];
        ToolTipService.SetToolTip(theme, "Choose system, light, or dark theme.");
        theme.SelectionChanged += async (_, _) =>
        {
            if (theme.SelectedItem is ComboBoxItem item && _session is not null)
            {
                var colorTheme = item.Tag?.ToString() ?? "system";
                await _session.SavePreferencesAsync(_session.BundleState.LocalizationCode, colorTheme);
                (Application.Current as App)?.MainWindow?.ApplyTheme(colorTheme);
            }
        };
        panel.Children.Add(theme);

        return new Border
        {
            Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Child = panel,
        };
    }

    private FrameworkElement RenderSetupStatusSection()
    {
        var panel = new StackPanel { Spacing = 10, Padding = new Thickness(16) };
        AutomationProperties.SetAutomationId(panel, "SetupStatusSection");
        AutomationProperties.SetName(panel, "Setup status");
        panel.Children.Add(new TextBlock
        {
            Text = SetupStatusTitle(),
            Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"],
        });

        if (_manifest?.Setup.Steps.Count > 0)
        {
            foreach (var step in _manifest.Setup.Steps)
            {
                var result = _setupRun?.Results.FirstOrDefault(candidate => string.Equals(candidate.Id, step.Id, StringComparison.Ordinal));
                panel.Children.Add(new TextBlock
                {
                    Text = $"{step.Label}: {result?.Status ?? "not run"}",
                    TextWrapping = TextWrapping.Wrap,
                });
            }
        }
        else
        {
            panel.Children.Add(new TextBlock { Text = "No setup steps are defined for this bundle." });
        }

        var runButton = new Button
        {
            Content = _setupRun?.Status == "ok" ? "Run setup again" : "Run setup",
            IsEnabled = _manifest?.Setup.Steps.Count > 0,
        };
        AutomationProperties.SetAutomationId(runButton, "RunSetupButton");
        AutomationProperties.SetName(runButton, runButton.Content.ToString());
        ToolTipService.SetToolTip(runButton, "Run the bundle setup checks and dependency probes.");
        runButton.Click += async (_, _) => await RunSetupAsync();
        panel.Children.Add(runButton);

        return new Border
        {
            Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Child = panel,
        };
    }

    private string SetupStatusTitle() => _setupRun?.Status switch
    {
        "ok" => "Setup ready",
        "failed" => "Setup needs attention",
        _ => "Setup not run",
    };

    private async Task RunSetupAsync()
    {
        if (_manifest is null)
        {
            return;
        }

        var results = new List<BundleSetupStepRunState>();
        AppendOutput("Running setup...");
        foreach (var step in _manifest.Setup.Steps)
        {
            var command = WindowsSetupKinds.CommandFor(step);
            if (command is null)
            {
                results.Add(SetupResult(step, null, "skipped", null));
                continue;
            }

            var workingDirectory = string.IsNullOrWhiteSpace(step.WorkingDirectory)
                ? _bundleRoot
                : ResolveBundlePath(step.WorkingDirectory);
            AppendOutput($"> {step.Label}: {command.Executable} {string.Join(" ", command.Arguments)}");
            try
            {
                var result = await _processRunner.RunAsync(new ProcessExecutionRequest
                {
                    Command = command,
                    WorkingDirectory = workingDirectory,
                    Timeout = TimeSpan.FromMinutes(10),
                    Environment = new Dictionary<string, string>(step.Environment)
                    {
                        ["GUI_FOR_CLI_BUNDLE_ROOT"] = _bundleRoot,
                        ["GUI_FOR_CLI_BUNDLE_WORKSPACE"] = _bundleWorkspace,
                    },
                });
                AppendOutput(result.StandardOutput);
                AppendOutput(result.StandardError);
                var status = result.ExitCode == 0 || step.Optional ? "ok" : "failed";
                results.Add(SetupResult(step, command, status, result.ExitCode));
                if (status == "failed")
                {
                    break;
                }
            }
            catch (Exception error) when (step.Optional)
            {
                AppendOutput($"Optional setup step failed: {error.Message}");
                results.Add(SetupResult(step, command, "ok", null));
            }
            catch (Exception error)
            {
                AppendOutput($"Setup failed: {error.Message}");
                results.Add(SetupResult(step, command, "failed", null));
                break;
            }
        }

        var failed = results.FirstOrDefault(result => result.Status == "failed");
        _setupRun = new BundleSetupRunState
        {
            Status = failed is null ? "ok" : "failed",
            Results = results,
            CompletedAt = DateTimeOffset.UtcNow.ToString("O"),
            Error = failed is null ? null : $"{failed.Label} failed.",
        };
        await SaveStateAsync();
        RenderSelectedPage();
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
            var pathBox = CreateTextBox(
                _configFilePaths.TryGetValue(control.Id, out var path) ? path : control.ConfigFile.Path,
                null,
                $"ConfigPath_{control.Id}",
                $"{control.Label} settings file");
            pathBox.Header = "Settings file";
            AutomationProperties.SetAutomationId(pathBox, $"ConfigPath_{control.Id}");
            AutomationProperties.SetName(pathBox, $"{control.Label} settings file");
            pathBox.TextChanged += (_, _) =>
            {
                _configFilePaths[control.Id] = pathBox.Text;
                _ = SaveStateAsync();
            };
            panel.Children.Add(RenderPathPickerRow(pathBox, PathPickerTarget.File, "Settings file"));
        }

        foreach (var setting in control.Settings)
        {
            var key = RenderingEngine.ConfigValueKey(control, setting);
            var label = string.IsNullOrWhiteSpace(setting.Label) ? setting.Id : setting.Label;
            var box = CreateTextBox(
                _configValues.TryGetValue(key, out var value) ? value : setting.Value ?? "",
                setting.Placeholder,
                $"Config_{control.Id}_{setting.Id}",
                label);
            box.Header = label;
            box.TextChanged += (_, _) =>
            {
                _configValues[key] = box.Text;
                if (_fieldValues.ContainsKey(setting.Id))
                {
                    _fieldValues[setting.Id] = box.Text;
                }

                _ = SaveStateAsync();
            };
            panel.Children.Add(string.Equals(setting.Kind, "path", StringComparison.Ordinal)
                ? RenderPathPickerRow(box, PickerTargetFor(setting.Id, label, setting.Placeholder), label)
                : box);
        }

        return panel;
    }

    private static TextBox CreateTextBox(string text, string? placeholder, string automationId, string automationName)
    {
        var box = new TextBox
        {
            Text = text,
            PlaceholderText = placeholder ?? "",
        };
        AutomationProperties.SetAutomationId(box, automationId);
        AutomationProperties.SetName(box, automationName);
        return box;
    }

    private FrameworkElement RenderPathPickerRow(TextBox box, PathPickerTarget target, string label)
    {
        var row = new Grid
        {
            ColumnSpacing = 8,
        };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var button = new Button
        {
            Content = "Choose...",
            VerticalAlignment = VerticalAlignment.Bottom,
            MinWidth = 96,
        };
        AutomationProperties.SetName(button, $"Choose {label}");
        AutomationProperties.SetAutomationId(button, $"{AutomationProperties.GetAutomationId(box)}_Choose");
        ToolTipService.SetToolTip(button, target == PathPickerTarget.Folder ? $"Choose folder for {label}" : $"Choose file for {label}");
        button.Click += async (_, _) =>
        {
            try
            {
                var selectedPath = await PickPathAsync(target);
                if (!string.IsNullOrWhiteSpace(selectedPath))
                {
                    box.Text = selectedPath;
                }
            }
            catch (Exception error)
            {
                AppendOutput($"Could not choose path for {label}: {error.Message}");
            }
        };

        Grid.SetColumn(box, 0);
        Grid.SetColumn(button, 1);
        row.Children.Add(box);
        row.Children.Add(button);
        return row;
    }

    private static async Task<string?> PickPathAsync(PathPickerTarget target)
    {
        return target == PathPickerTarget.Folder
            ? await PickFolderPathAsync()
            : await PickFilePathAsync();
    }

    private static async Task<string?> PickFilePathAsync()
    {
        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
        };
        picker.FileTypeFilter.Add("*");
        InitializePicker(picker);
        var file = await picker.PickSingleFileAsync();
        return file?.Path;
    }

    private static async Task<string?> PickFolderPathAsync()
    {
        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
        };
        picker.FileTypeFilter.Add("*");
        InitializePicker(picker);
        var folder = await picker.PickSingleFolderAsync();
        return folder?.Path;
    }

    private static void InitializePicker(object picker)
    {
        if (Application.Current is not App app || app.MainWindow is null)
        {
            throw new InvalidOperationException("No app window is available for the picker.");
        }

        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(app.MainWindow));
    }

    private static PathPickerTarget PickerTargetFor(string id, string label, string? placeholder)
    {
        var text = $"{id} {label} {placeholder}".ToLowerInvariant();
        return text.Contains("directory", StringComparison.Ordinal)
            || text.Contains("folder", StringComparison.Ordinal)
            || text.Contains("cache_path", StringComparison.Ordinal)
            || text.Contains("out_dir", StringComparison.Ordinal)
            || text.Contains("output_dir", StringComparison.Ordinal)
            || text.EndsWith("_dir", StringComparison.Ordinal)
                ? PathPickerTarget.Folder
                : PathPickerTarget.File;
    }

    private enum PathPickerTarget
    {
        File,
        Folder,
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
        ToolTipService.SetToolTip(button, action.Tooltip ?? action.Title);
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
        ToolTipService.SetToolTip(button, missing.Count > 0 ? $"Missing: {string.Join(", ", missing)}" : disabledReason ?? action.Tooltip ?? action.Title);
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

    private void CopyOutput_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(OutputBox.Text))
        {
            CopyOutputStatus.Text = "Nothing to copy";
            return;
        }

        var package = new DataPackage();
        package.SetText(OutputBox.Text);
        Clipboard.SetContent(package);
        CopyOutputStatus.Text = "Copied";
    }

    private void OutputResizeHandle_PointerPressed(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        _isResizingOutput = true;
        _outputResizeStartY = e.GetCurrentPoint(this).Position.Y;
        _outputResizeStartHeight = RootGridRowHeight(2);
        OutputResizeHandle.CapturePointer(e.Pointer);
    }

    private void OutputResizeHandle_PointerMoved(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (!_isResizingOutput)
        {
            return;
        }

        var delta = _outputResizeStartY - e.GetCurrentPoint(this).Position.Y;
        var nextHeight = Math.Clamp(_outputResizeStartHeight + delta, 120, 520);
        if (Content is Grid rootGrid)
        {
            rootGrid.RowDefinitions[2].Height = new GridLength(nextHeight);
        }
    }

    private void OutputResizeHandle_PointerReleased(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        _isResizingOutput = false;
        OutputResizeHandle.ReleasePointerCapture(e.Pointer);
    }

    private double RootGridRowHeight(int rowIndex) =>
        Content is Grid rootGrid ? rootGrid.RowDefinitions[rowIndex].ActualHeight : 220;

    private string ResolveBundlePath(string value)
    {
        if (Path.IsPathRooted(value))
        {
            throw new InvalidOperationException($"Bundle paths must be relative: {value}");
        }

        var candidate = Path.GetFullPath(Path.Combine(_bundleRoot, value));
        var root = Path.GetFullPath(_bundleRoot);
        if (!candidate.StartsWith($"{root}{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(candidate, root, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"Bundle path escapes bundle root: {value}");
        }

        return candidate;
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
