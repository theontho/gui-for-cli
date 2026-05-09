using GUIForCLIWindows.Core;

internal static partial class WindowsCoreTests
{
public static (string Name, Func<Task> Body)[] All() => new (string Name, Func<Task> Body)[]
{
    ("parses flat localization TOML with comments and multiline values", Sync(ParseLocalizationToml)),
    ("computes initial field, option, and config state", Sync(ComputesInitialState)),
    ("renders commands with required and optional placeholders", Sync(RenderCommands)),
    ("hydrates list rows from item values and templates", Sync(HydrateRows)),
    ("builds row context for action rendering", Sync(BuildsRowContext)),
    ("evaluates numeric action conditions", Sync(NumericActionConditions)),
    ("evaluates action visibility and disabled reasons", Sync(ActionVisibilityAndDisabledReasons)),
    ("evaluates disk precheck arithmetic expressions", Sync(NumericExpressions)),
    ("round trips flat TOML config values", Sync(RoundTripsFlatToml)),
    ("parses quoted TOML keys with separators safely", Sync(ParsesQuotedTomlKeys)),
    ("computes path extension from Windows paths", Sync(ComputesWindowsPathExtension)),
    ("applies data source payload with WebUI row precedence", Sync(AppliesDataSourcePayload)),
    ("localizes nested manifest values", Sync(LocalizesNestedManifestValues)),
    ("validates manifest schema contract", Sync(ValidatesManifestSchemaContract)),
    ("rejects malformed manifest schema shapes consistently", Sync(RejectsMalformedManifestSchemaShapes)),
    ("computes Windows app storage paths", Sync(ComputesWindowsStoragePaths)),
    ("persists bundle state and config TOML", PersistsBundleStateAndConfig),
    ("rejects config paths that escape bundle workspace", Sync(RejectsEscapingConfigPaths)),
    ("handles duplicate persisted field IDs", Sync(HandlesDuplicatePersistedFieldIDs)),
    ("routes Windows commands without shell quoting", Sync(RoutesWindowsCommands)),
    ("routes shell scripts to PowerShell siblings", RoutesShellScriptsToPowerShellSiblings),
    ("maps semantic icons to Fluent glyphs", Sync(MapsSemanticIconsToFluentGlyphs)),
    ("builds Windows setup commands", Sync(BuildsWindowsSetupCommands)),
    ("exposes Windows process hardening primitives", Sync(ExposesWindowsProcessHardeningPrimitives)),
    ("runs bundle data source and file state", RunsBundleDataSourceAndFileState),
    ("runs a simple redirected process", RunsSimpleRedirectedProcess),
    ("loads and localizes WGSExtract split manifest", Sync(LoadsAndLocalizesWgsExtract)),
};

static Func<Task> Sync(Action body) => () =>
{
    body();
    return Task.CompletedTask;
};

}
