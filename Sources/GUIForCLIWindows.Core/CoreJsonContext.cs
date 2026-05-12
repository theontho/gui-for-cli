using System.Text.Json.Serialization;

namespace GUIForCLIWindows.Core;

[JsonSourceGenerationOptions(PreferredObjectCreationHandling = JsonObjectCreationHandling.Populate)]
[JsonSerializable(typeof(BundleManifest))]
[JsonSerializable(typeof(BundleState))]
[JsonSerializable(typeof(DataSourcePayload))]
[JsonSerializable(typeof(string))]
internal sealed partial class CoreJsonContext : JsonSerializerContext;
