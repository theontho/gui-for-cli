using GUIForCLIWindows.Core;

var failed = 0;
foreach (var (name, body) in WindowsCoreTests.All())
{
    try
    {
        await body();
        Console.WriteLine($"PASS {name}");
    }
    catch (Exception error)
    {
        failed += 1;
        Console.Error.WriteLine($"FAIL {name}");
        Console.Error.WriteLine(error);
    }
}

if (failed > 0)
{
    Environment.Exit(1);
}
