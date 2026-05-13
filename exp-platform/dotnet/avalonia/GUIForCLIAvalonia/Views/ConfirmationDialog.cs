using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;
using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Views;

public static class ConfirmationDialog
{
    public static async Task<bool> ShowAsync(Window owner, ActionSpec action)
    {
        if (action.Confirm is not { } confirm)
        {
            return true;
        }

        var dialog = new Window
        {
            Title = string.IsNullOrWhiteSpace(confirm.Title) ? action.Title : confirm.Title,
            Width = 460,
            Height = string.IsNullOrWhiteSpace(confirm.RequiredText) ? 220 : 290,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            CanResize = false,
        };
        var panel = new StackPanel { Spacing = 12, Margin = new Thickness(18) };
        panel.Children.Add(new TextBlock { Text = confirm.Message, TextWrapping = Avalonia.Media.TextWrapping.Wrap });
        TextBox? prompt = null;
        if (!string.IsNullOrWhiteSpace(confirm.RequiredText))
        {
            prompt = new TextBox { Watermark = confirm.RequiredText };
            AutomationProperties.SetName(prompt, string.IsNullOrWhiteSpace(confirm.Prompt) ? "Confirmation prompt" : confirm.Prompt);
            panel.Children.Add(new TextBlock { Text = string.IsNullOrWhiteSpace(confirm.Prompt) ? $"Type {confirm.RequiredText} to continue." : confirm.Prompt });
            panel.Children.Add(prompt);
        }

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 8 };
        var cancel = new Button { Content = string.IsNullOrWhiteSpace(confirm.CancelButtonTitle) ? "Cancel" : confirm.CancelButtonTitle };
        var ok = new Button { Content = string.IsNullOrWhiteSpace(confirm.ConfirmButtonTitle) ? "Continue" : confirm.ConfirmButtonTitle };
        cancel.Click += (_, _) => dialog.Close(false);
        ok.Click += (_, _) => dialog.Close(prompt is null || string.Equals(prompt.Text, confirm.RequiredText, StringComparison.Ordinal));
        buttons.Children.Add(cancel);
        buttons.Children.Add(ok);
        panel.Children.Add(buttons);
        dialog.Content = panel;
        return await dialog.ShowDialog<bool>(owner);
    }
}
