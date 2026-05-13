using CommunityToolkit.Mvvm.ComponentModel;
using GUIForCLIWindows.Core;

namespace GUIForCLIWindows.ViewModels;

public sealed partial class GeneratedControlViewModel : ObservableObject
{
    public GeneratedControlViewModel(ControlSpec spec)
    {
        Spec = spec;
    }

    public ControlSpec Spec { get; }
    public string Id => Spec.Id;
    public string Kind => Spec.Kind;
    public string Label => Spec.Label;

    [ObservableProperty]
    private string value = "";
}
