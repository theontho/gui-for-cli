using GUIForCLIWindows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GUIForCLIWindows.Controls;

public sealed class ControlTemplateSelector : DataTemplateSelector
{
    public DataTemplate? TextTemplate { get; set; }
    public DataTemplate? PathTemplate { get; set; }
    public DataTemplate? DropdownTemplate { get; set; }
    public DataTemplate? ToggleTemplate { get; set; }
    public DataTemplate? CheckboxGroupTemplate { get; set; }
    public DataTemplate? InfoGridTemplate { get; set; }
    public DataTemplate? LibraryListTemplate { get; set; }
    public DataTemplate? ConfigEditorTemplate { get; set; }

    protected override DataTemplate? SelectTemplateCore(object item) =>
        item is GeneratedControlViewModel control ? TemplateFor(control.Kind) : base.SelectTemplateCore(item);

    protected override DataTemplate? SelectTemplateCore(object item, DependencyObject container) =>
        item is GeneratedControlViewModel control ? TemplateFor(control.Kind) : base.SelectTemplateCore(item, container);

    private DataTemplate? TemplateFor(string kind) => kind switch
    {
        "text" => TextTemplate,
        "path" => PathTemplate,
        "dropdown" => DropdownTemplate,
        "toggle" => ToggleTemplate,
        "checkboxGroup" => CheckboxGroupTemplate,
        "infoGrid" => InfoGridTemplate,
        "libraryList" => LibraryListTemplate,
        "configEditor" => ConfigEditorTemplate,
        _ => throw new NotSupportedException($"Unsupported control kind: {kind}"),
    };
}
