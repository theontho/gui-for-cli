using GUIForCLIWindows.Core;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GUIForCLIWindows.Pages;

public sealed partial class HomePage
{
    private async Task LoadBundleAsync()
    {
        if (_isLoading)
        {
            return;
        }

        _isLoading = true;
        try
        {
            var appPaths = WindowsAppPaths.ForCurrentUser();
            var startupBundle = ResolveStartupBundle();
            _bundleRoot = startupBundle.BundleRoot;
            var rawManifest = startupBundle.Manifest;
            _bundleWorkspace = appPaths.BundleWorkspace(rawManifest.Id);
            appPaths.EnsureBundleDirectories(rawManifest.Id);
            var bundleState = await BundleStateStore.LoadBundleStateAsync(_bundleWorkspace);
            var table = ManifestLoader.LoadStringTable(
                startupBundle.SharedResourceRoot,
                _bundleRoot,
                rawManifest,
                bundleState.LocalizationCode ?? rawManifest.DefaultLocalizationCode);
            _manifest = ManifestLoader.LocalizeManifest(rawManifest, table);
            _configFilePaths = BundleStateStore.InitialConfigFilePaths(_manifest, bundleState);
            _configValues = await BundleStateStore.InitialConfigValuesAsync(_manifest, _configFilePaths, _bundleWorkspace);
            _fieldValues = BundleStateStore.InitialFieldValues(_manifest, _configValues, bundleState);
            _checkedOptions = BundleStateStore.InitialCheckedOptions(_manifest, _configValues, bundleState);
            _manifest = await HydrateDataSourcesAsync(_manifest);

            BundleTitle.Text = _manifest.DisplayName;
            BundleSummary.Text = _manifest.Summary;
            AutomationProperties.SetAutomationId(SaveStateButton, "SaveStateButton");
            AutomationProperties.SetName(SaveStateButton, "Save bundle state");
            BundleInfoBar.Title = "Bundle loaded";
            BundleInfoBar.Message = $"{_manifest.Pages.Count} pages and {RenderingEngine.AllControls(_manifest).Count} controls loaded from {startupBundle.DisplayPath}.";
            BundleInfoBar.Severity = InfoBarSeverity.Success;
            PageSelector.ItemsSource = _manifest.Pages.Select(page => new PageChoice(page)).ToList();
            PageSelector.DisplayMemberPath = nameof(PageChoice.Title);
            PageSelector.SelectedIndex = 0;
            RenderSelectedPage();
        }
        catch (Exception error)
        {
            BundleInfoBar.Severity = InfoBarSeverity.Error;
            BundleInfoBar.Title = "Could not load bundle";
            BundleInfoBar.Message = error.Message;
            AppendOutput($"Load failed: {error}");
        }
        finally
        {
            _isLoading = false;
        }
    }

    private async Task<BundleManifest> HydrateDataSourcesAsync(BundleManifest manifest)
    {
        var pages = new List<BundlePage>();
        foreach (var page in manifest.Pages)
        {
            var sections = new List<PageSection>();
            foreach (var section in page.Sections)
            {
                var controls = new List<ControlSpec>();
                foreach (var control in section.Controls)
                {
                    if (control.DataSource is null)
                    {
                        controls.Add(control);
                        continue;
                    }

                    try
                    {
                        var payload = await _runtimeService.RunDataSourceAsync(control.DataSource, RenderContext(), _bundleRoot);
                        controls.Add(RenderingEngine.ApplyDataSourcePayload(control, payload));
                    }
                    catch (Exception error)
                    {
                        controls.Add(control);
                        AppendOutput($"Data source failed for {control.Label}: {error.Message}");
                    }
                }

                sections.Add(section with { Controls = controls });
            }

            pages.Add(page with { Sections = sections });
        }

        return manifest with { Pages = pages };
    }

    private static StartupBundle ResolveStartupBundle()
    {
        if (TryFindRepoRoot() is { } repoRoot)
        {
            var repoBundleRoot = Path.Combine(repoRoot, "Examples", "WGSExtract");
            if (Directory.Exists(repoBundleRoot) && File.Exists(Path.Combine(repoBundleRoot, "manifest.json")))
            {
                return new StartupBundle(
                    repoRoot,
                    repoBundleRoot,
                    ManifestLoader.LoadManifestFromRoot(repoBundleRoot),
                    "Examples\\WGSExtract");
            }
        }

        var installedBundleRoot = Path.Combine(AppContext.BaseDirectory, "Resources", "Bundles", "WGSExtract");
        if (Directory.Exists(installedBundleRoot) && File.Exists(Path.Combine(installedBundleRoot, "manifest.json")))
        {
            return new StartupBundle(
                AppContext.BaseDirectory,
                installedBundleRoot,
                ManifestLoader.LoadManifestFromRoot(installedBundleRoot),
                "installed WGSExtract bundle");
        }

        throw new InvalidOperationException("Could not find the WGSExtract bundle in the repository checkout or installed app resources.");
    }

    private static string? TryFindRepoRoot()
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

        return null;
    }

    private sealed record StartupBundle(string SharedResourceRoot, string BundleRoot, BundleManifest Manifest, string DisplayPath);

}
