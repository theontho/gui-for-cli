using GUIForCLIWindows.Core;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GUIForCLIWindows.Pages;

public sealed partial class HomePage
{
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

}
