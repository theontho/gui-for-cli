using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Views;

public sealed class LibraryRowRenderer
{
    private readonly ActionRenderer _actions;
    private readonly RenderContext _sectionContext;

    public LibraryRowRenderer(ActionRenderer actions, RenderContext sectionContext)
    {
        _actions = actions;
        _sectionContext = sectionContext;
    }

    public Control Render(ControlSpec control, ListRowSpec row)
    {
        var rowContext = RenderingEngine.RowContext(_sectionContext, row);
        var card = new Border
        {
            CornerRadius = new CornerRadius(8),
            BorderBrush = Brushes.Gray,
            BorderThickness = new Thickness(1),
            Padding = new Thickness(10),
            Margin = new Thickness(0, 0, 0, 6),
        };
        var panel = new StackPanel { Spacing = 6 };
        panel.Children.Add(Header(row));
        if (control.Columns.Count > 0)
        {
            panel.Children.Add(Columns(control, row));
        }

        if (control.RowActions.Count > 0)
        {
            var actions = new WrapPanel { Orientation = Orientation.Horizontal };
            foreach (var action in control.RowActions.Where(action => RenderingEngine.IsActionVisible(action, rowContext)))
            {
                var rendered = _actions.Render(action, rowContext);
                rendered.Margin = new Thickness(0, 0, 8, 4);
                actions.Children.Add(rendered);
            }

            panel.Children.Add(actions);
        }

        card.Child = panel;
        AutomationProperties.SetName(card, row.Title ?? row.Id ?? "Library row");
        if (!string.IsNullOrWhiteSpace(row.Tooltip))
        {
            ToolTip.SetTip(card, row.Tooltip);
        }

        return card;
    }

    private static Control Header(ListRowSpec row)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        panel.Children.Add(new TextBlock { Text = row.Title ?? row.Id ?? "Row", FontWeight = FontWeight.SemiBold });
        if (!string.IsNullOrWhiteSpace(row.Status))
        {
            panel.Children.Add(new TextBlock { Text = row.Status, Opacity = 0.75 });
        }

        foreach (var tag in row.Tags)
        {
            panel.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(999),
                Padding = new Thickness(8, 2),
                Background = Brushes.DimGray,
                Child = new TextBlock { Text = tag.Title, Foreground = Brushes.White, FontSize = 12 },
            });
        }

        return panel;
    }

    private static Control Columns(ControlSpec control, ListRowSpec row)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*"), RowSpacing = 2, ColumnSpacing = 10 };
        var rowIndex = 0;
        foreach (var column in control.Columns)
        {
            if (!row.Values.TryGetValue(column.Id, out var value) || string.IsNullOrWhiteSpace(value))
            {
                continue;
            }

            grid.RowDefinitions.Add(new RowDefinition(GridLength.Auto));
            var label = new TextBlock { Text = column.Title, FontWeight = FontWeight.SemiBold };
            var text = new TextBlock { Text = value, TextWrapping = TextWrapping.Wrap };
            Grid.SetRow(label, rowIndex);
            Grid.SetColumn(label, 0);
            Grid.SetRow(text, rowIndex);
            Grid.SetColumn(text, 1);
            grid.Children.Add(label);
            grid.Children.Add(text);
            rowIndex += 1;
        }

        return grid;
    }
}
