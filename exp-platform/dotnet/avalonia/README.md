# Avalonia renderer experiment

This cross-platform .NET desktop experiment renders GUI for CLI bundles with Avalonia UI while reusing the existing C# bundle/runtime core from `exp-platform/windows/dotnet/GUIForCLIWindows.Core`.

```bash
make setup PLATFORM=webui
make build PLATFORM=avalonia
make test PLATFORM=avalonia
make run PLATFORM=avalonia BUNDLE=examples/WGSExtract
make benchmark ARGS='avalonia'
```

The app loads split-page bundles, localized string tables, config/state from a platform Application Support path, section/control data sources, action conditions, setup steps, row actions, terminal tabs with cancellation, RTL layout, manifest-configurable terminal direction, LTR path fields, and first-render benchmark output.
