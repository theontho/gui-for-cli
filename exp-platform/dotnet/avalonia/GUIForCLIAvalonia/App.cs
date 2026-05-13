using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Themes.Fluent;
using GUIForCLIAvalonia.Services;
using GUIForCLIAvalonia.Views;

namespace GUIForCLIAvalonia;

public sealed class App : Application
{
    public static DesktopOptions Options { get; set; } = DesktopOptions.Parse([]);

    public override void Initialize()
    {
        Styles.Add(new FluentTheme());
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.MainWindow = new MainWindow(Options);
        }

        base.OnFrameworkInitializationCompleted();
    }
}
