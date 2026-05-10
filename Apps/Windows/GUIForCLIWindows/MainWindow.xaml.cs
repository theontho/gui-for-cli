using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using GUIForCLIWindows.Core;
using GUIForCLIWindows.Pages;
using Microsoft.UI.Xaml.Input;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace GUIForCLIWindows;

public sealed partial class MainWindow : Window
{
    private const string LibraryPageID = "library";
    private const string SettingsPageID = "settings";
    private bool _isLoadingNavigation;
    private bool _hasManifestSettingsPage;
    private AppBundleSession? _bundleSession;
    private bool _isResizingPane;

    public MainWindow()
    {
        InitializeComponent();

        Title = "GUI for CLI";
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        AppWindow.SetIcon("Assets/AppIcon.ico");
        NavFrame.Loaded += async (_, _) => await LoadNavigationAsync();
    }

    private void TitleBar_PaneToggleRequested(TitleBar sender, object args)
    {
        NavView.IsPaneOpen = !NavView.IsPaneOpen;
    }

    private void TitleBar_BackRequested(TitleBar sender, object args)
    {
        NavFrame.GoBack();
    }

    private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (_isLoadingNavigation)
        {
            return;
        }

        if (args.IsSettingsSelected)
        {
            _ = PersistSelectedPageAsync(SettingsPageID);
            NavFrame.Navigate(_hasManifestSettingsPage ? typeof(HomePage) : typeof(SettingsPage), NavigationParameter(SettingsPageID));
        }
        else if (args.SelectedItem is NavigationViewItem item)
        {
            if (item.Tag is string pageID && pageID.StartsWith("page:", StringComparison.Ordinal))
            {
                var selectedPageID = pageID["page:".Length..];
                _ = PersistSelectedPageAsync(selectedPageID);
                NavFrame.Navigate(typeof(HomePage), NavigationParameter(selectedPageID));
                return;
            }

            throw new InvalidOperationException($"Unknown navigation item tag: {item.Tag}");
        }
    }

    private async Task LoadNavigationAsync()
    {
        if (NavView.MenuItems.Count > 0)
        {
            return;
        }

        _isLoadingNavigation = true;
        try
        {
            var repoRoot = FindRepoRoot();
            var bundleRoot = Path.Combine(repoRoot, "Examples", "WGSExtract");
            _bundleSession = await AppBundleSession.LoadAsync(repoRoot, bundleRoot);
            var manifest = _bundleSession.Manifest;

            AppTitleBar.Title = manifest.DisplayName;
            AppTitleBar.IconSource = new FontIconSource { Glyph = WindowsIconMapper.GlyphFor(manifest.IconName) };
            Title = manifest.DisplayName;
            BundlePaneIcon.Glyph = WindowsIconMapper.GlyphFor(manifest.IconName);
            BundlePaneTitle.Text = manifest.DisplayName;
            BundlePaneSummary.Text = manifest.Summary;
            ApplyTheme(_bundleSession.BundleState.ColorTheme);
            NavView.MenuItems.Clear();
            string? firstPageID = null;
            NavigationViewItem? firstItem = null;
            NavigationViewItem? selectedItem = null;
            string? previousGroup = null;
            var persistedPageID = manifest.Pages.Any(page => string.Equals(page.Id, _bundleSession.BundleState.SelectedPageID, StringComparison.Ordinal))
                ? _bundleSession.BundleState.SelectedPageID
                : null;

            foreach (var page in manifest.Pages)
            {
                if (string.Equals(page.Id, LibraryPageID, StringComparison.Ordinal))
                {
                    var libraryItem = CreatePageNavigationItem(page);
                    NavView.FooterMenuItems.Insert(0, libraryItem);
                    if (string.Equals(page.Id, persistedPageID, StringComparison.Ordinal))
                    {
                        selectedItem = libraryItem;
                    }

                    continue;
                }

                if (string.Equals(page.Id, SettingsPageID, StringComparison.Ordinal))
                {
                    _hasManifestSettingsPage = true;
                    if (NavView.SettingsItem is NavigationViewItem settingsItem)
                    {
                        settingsItem.Content = page.Title;
                        AutomationProperties.SetName(settingsItem, page.Title);
                        if (string.Equals(page.Id, persistedPageID, StringComparison.Ordinal))
                        {
                            selectedItem = settingsItem;
                        }
                    }

                    continue;
                }

                if (!string.IsNullOrWhiteSpace(page.SidebarGroup)
                    && !string.Equals(page.SidebarGroup, previousGroup, StringComparison.Ordinal))
                {
                    NavView.MenuItems.Add(new NavigationViewItemHeader { Content = page.SidebarGroup });
                    previousGroup = page.SidebarGroup;
                }

                firstPageID ??= page.Id;
                var item = CreatePageNavigationItem(page);
                firstItem ??= item;
                if (string.Equals(page.Id, persistedPageID, StringComparison.Ordinal))
                {
                    selectedItem = item;
                }

                NavView.MenuItems.Add(item);
            }

            var initialPageID = persistedPageID ?? firstPageID;
            if (initialPageID is not null && (selectedItem ?? firstItem) is { } initialItem)
            {
                NavView.SelectedItem = initialItem;
                NavFrame.Navigate(typeof(HomePage), NavigationParameter(initialPageID));
            }
        }
        catch (Exception error)
        {
            NavFrame.Navigate(typeof(HomePage), NavigationParameter(null));
            throw new InvalidOperationException("Could not build bundle navigation.", error);
        }
        finally
        {
            _isLoadingNavigation = false;
        }
    }

    private static NavigationViewItem CreatePageNavigationItem(BundlePage page)
    {
        var item = new NavigationViewItem
        {
            Content = page.Title,
            Tag = $"page:{page.Id}",
            Icon = new FontIcon { Glyph = WindowsIconMapper.GlyphFor(page.IconName) },
        };
        AutomationProperties.SetName(item, page.Title);
        AutomationProperties.SetAutomationId(item, $"BundlePage_{page.Id}");
        return item;
    }

    private BundlePageNavigationParameter? NavigationParameter(string? pageID) =>
        _bundleSession is null ? null : new BundlePageNavigationParameter(_bundleSession, pageID);

    private async Task PersistSelectedPageAsync(string pageID)
    {
        if (_bundleSession is null)
        {
            return;
        }

        await _bundleSession.SaveStateAsync(pageID);
    }

    public void ApplyTheme(string? colorTheme)
    {
        NavFrame.RequestedTheme = colorTheme switch
        {
            "light" => ElementTheme.Light,
            "dark" => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };
    }

    public async Task ReloadBundleAsync()
    {
        var selectedPageID = _bundleSession?.BundleState.SelectedPageID;
        NavView.MenuItems.Clear();
        NavView.FooterMenuItems.Clear();
        _hasManifestSettingsPage = false;
        _bundleSession = null;
        await LoadNavigationAsync();
        if (selectedPageID is not null)
        {
            NavFrame.Navigate(typeof(HomePage), NavigationParameter(selectedPageID));
        }
    }

    private void PaneResizeHandle_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        _isResizingPane = true;
        PaneResizeHandle.CapturePointer(e.Pointer);
    }

    private void PaneResizeHandle_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_isResizingPane)
        {
            return;
        }

        var x = e.GetCurrentPoint(NavView).Position.X;
        NavView.OpenPaneLength = Math.Clamp(x, 180, 420);
    }

    private void PaneResizeHandle_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        _isResizingPane = false;
        PaneResizeHandle.ReleasePointerCapture(e.Pointer);
    }

    private static string FindRepoRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "Package.swift"))
                && Directory.Exists(Path.Combine(directory.FullName, "Examples", "WGSExtract")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new InvalidOperationException("Could not find repository root.");
    }
}
