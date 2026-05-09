using GUIForCLIWindows.Core;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GUIForCLIWindows.Pages;

public sealed partial class HomePage : Page
{
    private readonly SimpleProcessRunner _processRunner = new();
    private readonly BundleRuntimeService _runtimeService;
    private BundleManifest? _manifest;
    private string _bundleRoot = "";
    private string _bundleWorkspace = "";
    private Dictionary<string, string> _fieldValues = [];
    private Dictionary<string, string> _configValues = [];
    private Dictionary<string, IReadOnlyList<string>> _checkedOptions = [];
    private Dictionary<string, string> _configFilePaths = [];
    private bool _isLoading;

    public HomePage()
    {
        InitializeComponent();
        _runtimeService = new BundleRuntimeService(_processRunner);
        Loaded += async (_, _) => await LoadBundleAsync();
    }

    private void PageSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isLoading)
        {
            RenderSelectedPage();
        }
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

    private sealed record PageChoice(BundlePage Page)
    {
        public string Title => Page.SidebarGroup is null ? Page.Title : $"{Page.SidebarGroup} / {Page.Title}";
    }
}
