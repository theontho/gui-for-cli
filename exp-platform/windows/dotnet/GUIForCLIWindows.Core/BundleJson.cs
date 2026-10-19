using System.Text.Json;

namespace GUIForCLIWindows.Core;

/// Bundle manifests and page files are JSON with `//` and `/* */` comments.
public static class BundleJson
{
    public static readonly JsonDocumentOptions DocumentOptions = new()
    {
        CommentHandling = JsonCommentHandling.Skip,
    };
}
