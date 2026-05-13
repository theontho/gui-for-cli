using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using GUIForCLIAvalonia.Services;
using GUIForCLIWindows.Core;

namespace GUIForCLIAvalonia.Views;

public sealed class MainWindow : Window
{
    private readonly DesktopOptions _options;
    private readonly TerminalManager _terminal = new();
    private readonly StackPanel _navigation = new() { Spacing = 4, Margin = new Thickness(8) };
    private readonly ScrollViewer _contentScroll = new();
    private readonly Grid _mainGrid = new();
    private readonly TerminalPane _terminalPane;
    private DesktopBundleSession? _session;
    private string? _selectedPageID;

    public MainWindow(DesktopOptions options)
    {
        _options = options;
        _terminalPane = new TerminalPane(_terminal);
        Title = "GUI for CLI Avalonia";
        MinWidth = 980;
        MinHeight = 680;
        Width = 1180;
        Height = 780;
        Content = BuildShell();
        Opened += async (_, _) => await LoadBundleAsync();
        Closed += (_, _) => CancelRunningTabs();
    }

    private Control BuildShell()
    {
        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition(new GridLength(1, GridUnitType.Star)));
        root.RowDefinitions.Add(new RowDefinition(new GridLength(230)));
        _mainGrid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(250)));
        _mainGrid.ColumnDefinitions.Add(new ColumnDefinition(new GridLength(1, GridUnitType.Star)));

        var sidebar = new Border
        {
            BorderBrush = Brushes.Gray,
            BorderThickness = new Thickness(0, 0, 1, 0),
            Child = new ScrollViewer { Content = _navigation },
        };
        AutomationProperties.SetName(sidebar, "Bundle pages");
        _mainGrid.Children.Add(sidebar);
        Grid.SetColumn(_contentScroll, 1);
        _mainGrid.Children.Add(_contentScroll);
        root.Children.Add(_mainGrid);
        Grid.SetRow(_terminalPane.Control, 1);
        root.Children.Add(_terminalPane.Control);
        return root;
    }

    private async Task LoadBundleAsync()
    {
        try
        {
            var repoRoot = RepoLocator.ResolveRepoRoot(_options.RepoRoot);
            var bundleRoot = RepoLocator.ResolveBundleRoot(repoRoot, _options.BundleRoot);
            _session = await DesktopBundleSession.LoadAsync(repoRoot, bundleRoot);
            _selectedPageID = ValidPageID(_session.BundleState.SelectedPageID) ?? _session.Manifest.Pages.FirstOrDefault()?.Id;
            Title = $"{_session.Manifest.DisplayName} - GUI for CLI Avalonia";
            FlowDirection = LayoutDirection.InterfaceDirection(_session.BundleState);
            _terminalPane.ApplyManifest(_session.Manifest);
            foreach (var message in _session.StartupMessages)
            {
                _terminal.AppendGeneral(message);
            }

            BuildNavigation();
            RenderSelectedPage();
            PrintBenchmarkMarker();
        }
        catch (Exception error)
        {
            _terminal.AppendGeneral($"Could not load bundle: {error.Message}");
            _contentScroll.Content = ErrorBlock(error.Message);
        }
    }

    private void BuildNavigation()
    {
        if (_session is null)
        {
            return;
        }

        _navigation.Children.Clear();
        _navigation.Children.Add(new TextBlock
        {
            Text = $"{IconText.For(_session.Manifest)} {_session.Manifest.DisplayName}",
            FontSize = 20,
            FontWeight = FontWeight.SemiBold,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 4),
        });
        if (!string.IsNullOrWhiteSpace(_session.Manifest.Summary))
        {
            _navigation.Children.Add(new TextBlock { Text = _session.Manifest.Summary, TextWrapping = TextWrapping.Wrap, Opacity = 0.72 });
        }

        string? previousGroup = null;
        foreach (var page in _session.Manifest.Pages)
        {
            if (!string.IsNullOrWhiteSpace(page.SidebarGroup) && page.SidebarGroup != previousGroup)
            {
                _navigation.Children.Add(new TextBlock
                {
                    Text = page.SidebarGroup,
                    FontWeight = FontWeight.SemiBold,
                    Margin = new Thickness(0, 10, 0, 0),
                });
                previousGroup = page.SidebarGroup;
            }

            var button = new Button
            {
                Content = $"{IconText.For(page)} {page.Title}",
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                FontWeight = page.Id == _selectedPageID ? FontWeight.SemiBold : FontWeight.Normal,
            };
            AutomationProperties.SetName(button, page.Title);
            ToolTip.SetTip(button, string.IsNullOrWhiteSpace(page.Summary) ? page.Title : page.Summary);
            button.Click += async (_, _) => await SelectPageAsync(page.Id);
            _navigation.Children.Add(button);
        }
    }

    private async Task SelectPageAsync(string pageID)
    {
        _selectedPageID = pageID;
        if (_session is not null)
        {
            await _session.SaveStateAsync(pageID);
        }

        BuildNavigation();
        RenderSelectedPage();
    }

    private void RenderSelectedPage()
    {
        if (_session is null)
        {
            return;
        }

        var page = _session.Manifest.Pages.FirstOrDefault(candidate => candidate.Id == _selectedPageID) ?? _session.Manifest.Pages.FirstOrDefault();
        _contentScroll.Content = page is null
            ? ErrorBlock("Bundle does not define any pages.")
            : new PageRenderer(_session, _terminal, this, _selectedPageID, async () => await ReloadCurrentPageAsync()).Render(page);
    }

    private async Task ReloadCurrentPageAsync()
    {
        if (_session is null)
        {
            return;
        }

        try
        {
            var messages = await _session.RefreshDataSourcesAsync();
            foreach (var message in messages)
            {
                _terminal.AppendGeneral(message);
            }

            _terminalPane.ApplyManifest(_session.Manifest);
            BuildNavigation();
            RenderSelectedPage();
        }
        catch (Exception error)
        {
            _terminal.AppendGeneral($"Could not refresh page: {error.Message}");
            _contentScroll.Content = ErrorBlock(error.Message);
        }
    }

    public async Task ReloadBundleForPreferencesAsync()
    {
        if (_session is null)
        {
            return;
        }

        var pageID = _selectedPageID;
        _session = await DesktopBundleSession.LoadAsync(_session.RepoRoot, _session.BundleRoot);
        _selectedPageID = ValidPageID(pageID) ?? _session.Manifest.Pages.FirstOrDefault()?.Id;
        FlowDirection = LayoutDirection.InterfaceDirection(_session.BundleState);
        BuildNavigation();
        RenderSelectedPage();
    }

    private string? ValidPageID(string? pageID) =>
        _session?.Manifest.Pages.Any(page => page.Id == pageID) == true ? pageID : null;

    private static TextBlock ErrorBlock(string message) => new()
    {
        Text = message,
        Margin = new Thickness(24),
        TextWrapping = TextWrapping.Wrap,
    };

    private void PrintBenchmarkMarker()
    {
        if (!_options.Benchmark)
        {
            return;
        }

        Console.WriteLine($"GFC_AVALONIA_FIRST_RENDER_MS={_options.BootTimer.Elapsed.TotalMilliseconds:0.0}");
        if (_options.Once)
        {
            DispatcherTimer.RunOnce(Close, TimeSpan.FromMilliseconds(250));
        }
    }

    private void CancelRunningTabs()
    {
        foreach (var tab in _terminal.Tabs.Where(tab => tab.IsRunning).ToList())
        {
            _terminal.Close(tab);
        }
    }
}
