using GUIForCLIWindows.Core;

internal static partial class WindowsCoreTests
{
static string FindRepoRoot()
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

static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"Expected {expected}, got {actual}");
    }
}

static void SequenceEqual<T>(IEnumerable<T> expected, IEnumerable<T> actual)
{
    var expectedList = expected.ToList();
    var actualList = actual.ToList();
    if (!expectedList.SequenceEqual(actualList))
    {
        throw new InvalidOperationException($"Expected [{string.Join(", ", expectedList)}], got [{string.Join(", ", actualList)}]");
    }
}

static void Throws<TException>(Action body)
    where TException : Exception
{
    try
    {
        body();
    }
    catch (TException)
    {
        return;
    }

    throw new InvalidOperationException($"Expected {typeof(TException).Name}.");
}
}
