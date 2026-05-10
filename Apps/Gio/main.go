package main

import (
	"fmt"
	"os"
	"time"

	"gioui.org/app"
	"gioui.org/unit"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
	"github.com/theontho/gui-for-cli/apps/gio/internal/ui"
)

func main() {
	startedAt := time.Now()
	printMetric(startedAt, "processStarted")

	loadedBundle, err := bundle.Load(bundle.LoadOptions{
		BundleRoot:         os.Getenv("GFC_GIO_BUNDLE"),
		BuiltinStringsRoot: os.Getenv("GFC_GIO_BUILTIN_STRINGS"),
		RepoRoot:           os.Getenv("GFC_GIO_REPO_ROOT"),
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "gio bundle load failed: %v\n", err)
		os.Exit(1)
	}
	printMetric(startedAt, "bundleLoaded")

	window := new(app.Window)
	window.Option(
		app.Title(fmt.Sprintf("%s (Gio)", loadedBundle.Manifest.DisplayName)),
		app.Size(unit.Dp(1440), unit.Dp(920)),
	)
	printMetric(startedAt, "windowConfigured")

	go func() {
		if err := ui.Run(window, loadedBundle, startedAt); err != nil {
			fmt.Fprintf(os.Stderr, "gio app failed: %v\n", err)
			os.Exit(1)
		}
		os.Exit(0)
	}()

	app.Main()
}

func printMetric(startedAt time.Time, name string) {
	fmt.Printf("metric %s_ms=%.1f\n", name, time.Since(startedAt).Seconds()*1000)
}
