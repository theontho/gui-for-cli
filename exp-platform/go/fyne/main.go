package main

import (
	"flag"
	"fmt"
	"os"
	"time"

	"fyne.io/fyne/v2/app"

	"github.com/theontho/gui-for-cli/apps/fyne/internal/bundle"
	"github.com/theontho/gui-for-cli/apps/fyne/internal/ui"
)

func main() {
	startedAt := time.Now()
	printMetric(startedAt, "processStarted")

	var bundleRoot string
	var builtinStringsRoot string
	var repoRoot string
	var locale string
	var validateOnly bool
	flag.StringVar(&bundleRoot, "bundle", envOrEmpty("GFC_FYNE_BUNDLE"), "bundle root containing manifest.json")
	flag.StringVar(&builtinStringsRoot, "builtin-strings", envOrEmpty("GFC_FYNE_BUILTIN_STRINGS"), "built-in string table root")
	flag.StringVar(&repoRoot, "repo-root", envOrEmpty("GFC_FYNE_REPO_ROOT"), "repository root for development resource lookup")
	flag.StringVar(&locale, "locale", envOrEmpty("GFC_FYNE_LOCALE"), "locale code to load")
	flag.BoolVar(&validateOnly, "validate-only", false, "load the bundle and exit without opening a window")
	flag.Parse()

	loadedBundle, err := bundle.Load(bundle.LoadOptions{
		BundleRoot:         bundleRoot,
		BuiltinStringsRoot: builtinStringsRoot,
		RepoRoot:           repoRoot,
		LocalizationCode:   locale,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "fyne bundle load failed: %v\n", err)
		os.Exit(1)
	}
	printMetric(startedAt, "bundleLoaded")
	if validateOnly {
		fmt.Printf("validated %s with %d pages\n", loadedBundle.Manifest.DisplayName, len(loadedBundle.Manifest.Pages))
		return
	}

	fyneApp := app.NewWithID("dev.guiforcli.fyne")
	fyneApp.SetIcon(nil)
	if err := ui.Run(fyneApp, loadedBundle, ui.RunOptions{StartedAt: startedAt}); err != nil {
		fmt.Fprintf(os.Stderr, "fyne app failed: %v\n", err)
		os.Exit(1)
	}
}

func envOrEmpty(name string) string {
	return os.Getenv(name)
}

func printMetric(startedAt time.Time, name string) {
	fmt.Printf("metric %s_ms=%.1f\n", name, time.Since(startedAt).Seconds()*1000)
}
