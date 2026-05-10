using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using GUIForCLIWindows.Core;
using GUIForCLIWindows.Pages;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace GUIForCLIWindows;

public sealed partial class MainWindow : Window
{
    private const string LibraryPageID = "library";
    private const string SettingsPageID = "settings";
    private bool _isLoadingNavigation;
    private bool _hasManifestSettingsPage;

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
            NavFrame.Navigate(_hasManifestSettingsPage ? typeof(HomePage) : typeof(SettingsPage), SettingsPageID);
        }
        else if (args.SelectedItem is NavigationViewItem item)
        {
            if (item.Tag is string pageID && pageID.StartsWith("page:", StringComparison.Ordinal))
            {
                NavFrame.Navigate(typeof(HomePage), pageID["page:".Length..]);
                return;
            }

            if (string.Equals(item.Tag?.ToString(), "about", StringComparison.Ordinal))
            {
                NavFrame.Navigate(typeof(AboutPage));
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
            var rawManifest = ManifestLoader.LoadManifestFromRoot(bundleRoot);
            var appPaths = WindowsAppPaths.ForCurrentUser();
            var bundleWorkspace = appPaths.BundleWorkspace(rawManifest.Id);
            var bundleState = await BundleStateStore.LoadBundleStateAsync(bundleWorkspace);
            var table = ManifestLoader.LoadStringTable(repoRoot, bundleRoot, rawManifest, bundleState.LocalizationCode ?? rawManifest.DefaultLocalizationCode);
            var manifest = ManifestLoader.LocalizeManifest(rawManifest, table);

            AppTitleBar.Title = manifest.DisplayName;
            Title = manifest.DisplayName;
            NavView.MenuItems.Clear();
            string? firstPageID = null;
            string? previousGroup = null;

            foreach (var page in manifest.Pages)
            {
                if (string.Equals(page.Id, LibraryPageID, StringComparison.Ordinal))
                {
                    NavView.FooterMenuItems.Insert(0, CreatePageNavigationItem(page));
                    continue;
                }

                if (string.Equals(page.Id, SettingsPageID, StringComparison.Ordinal))
                {
                    _hasManifestSettingsPage = true;
                    if (NavView.SettingsItem is NavigationViewItem settingsItem)
                    {
                        settingsItem.Content = page.Title;
                        AutomationProperties.SetName(settingsItem, page.Title);
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
                NavView.MenuItems.Add(CreatePageNavigationItem(page));
            }

            if (firstPageID is not null && NavView.MenuItems.OfType<NavigationViewItem>().FirstOrDefault() is { } firstItem)
            {
                NavView.SelectedItem = firstItem;
                NavFrame.Navigate(typeof(HomePage), firstPageID);
            }
        }
        catch (Exception error)
        {
            NavFrame.Navigate(typeof(HomePage), null);
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
