using System.Text.Json;

namespace GUIForCLIWindows.Core;

public static class ManifestSchemaContract
{
    public const string SchemaFileName = "manifest.schema.json";
    public const string SchemaId = "https://gui-for-cli.dev/schema/manifest.schema.json";

    public static void ValidateSchemaDocument(string schemaJson)
    {
        using var document = JsonDocument.Parse(schemaJson);
        var root = document.RootElement;
        RequireString(root, "$schema");
        RequireString(root, "$id");
        if (root.GetProperty("$id").GetString() != SchemaId)
        {
            throw new InvalidDataException($"Manifest schema $id must be {SchemaId}.");
        }

        RequireObject(root, "$defs");
        var defs = root.GetProperty("$defs");
        foreach (var requiredDefinition in new[] { "page", "section", "control", "action", "command", "setupStep" })
        {
            RequireObject(defs, requiredDefinition);
        }
    }

    public static void ValidateManifestDocument(string manifestJson)
    {
        using var document = JsonDocument.Parse(manifestJson);
        ValidateManifestRoot(document.RootElement);
    }

    public static void ValidateManifestRoot(JsonElement root)
    {
        RequireString(root, "id");
        RequireString(root, "displayName");
        if (!root.TryGetProperty("pages", out var pages) || pages.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException("Manifest must contain a pages array.");
        }

        foreach (var page in pages.EnumerateArray())
        {
            if (page.ValueKind == JsonValueKind.String)
            {
                if (string.IsNullOrWhiteSpace(page.GetString()))
                {
                    throw new InvalidDataException("Manifest page file references must not be empty.");
                }

                continue;
            }

            ValidatePage(page);
        }
    }

    public static void ValidatePageDocument(string pageJson)
    {
        using var document = JsonDocument.Parse(pageJson);
        ValidatePage(document.RootElement);
    }

    private static void ValidatePage(JsonElement page)
    {
        RequireString(page, "id");
        RequireString(page, "title");
        if (page.TryGetProperty("sections", out var sections))
        {
            RequireArray(page, "sections");
            foreach (var section in sections.EnumerateArray())
            {
                ValidateSection(section);
            }
        }
    }

    private static void ValidateSection(JsonElement section)
    {
        RequireString(section, "id");
        if (section.TryGetProperty("controls", out var controls))
        {
            RequireArray(section, "controls");
            foreach (var control in controls.EnumerateArray())
            {
                RequireString(control, "id");
                RequireString(control, "kind");
            }
        }

        if (section.TryGetProperty("actions", out var actions))
        {
            RequireArray(section, "actions");
            foreach (var action in actions.EnumerateArray())
            {
                RequireString(action, "id");
                RequireString(action, "title");
                RequireObject(action, "command");
                RequireString(action.GetProperty("command"), "executable");
            }
        }
    }

    private static void RequireString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property)
            || property.ValueKind != JsonValueKind.String
            || string.IsNullOrWhiteSpace(property.GetString()))
        {
            throw new InvalidDataException($"Required string property '{propertyName}' is missing or empty.");
        }
    }

    private static void RequireArray(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException($"Required array property '{propertyName}' is missing.");
        }
    }

    private static void RequireObject(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException($"Required object property '{propertyName}' is missing.");
        }
    }
}
