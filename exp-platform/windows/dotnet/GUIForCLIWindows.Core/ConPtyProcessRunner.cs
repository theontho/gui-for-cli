using System.Runtime.InteropServices;

namespace GUIForCLIWindows.Core;

public sealed class ConPtyProcessRunner
{
    private readonly SimpleProcessRunner _fallbackRunner = new();

    public static bool IsAvailable => OperatingSystem.IsWindowsVersionAtLeast(10, 0, 17763);

    public async Task<ProcessExecutionResult> RunAsync(ProcessExecutionRequest request, CancellationToken cancellationToken = default)
    {
        if (!IsAvailable)
        {
            throw new PlatformNotSupportedException("ConPTY requires Windows 10 1809 or newer.");
        }

        // The MVP terminal surface is append-only. Keep action execution on the hardened
        // process runner while exposing a ConPTY-specific runner boundary for the terminal UI.
        return await _fallbackRunner.RunAsync(request, cancellationToken).ConfigureAwait(false);
    }

    public static void EnsureNativeEntrypointsAvailable()
    {
        if (!IsAvailable)
        {
            throw new PlatformNotSupportedException("ConPTY requires Windows 10 1809 or newer.");
        }

        _ = NativeMethods.CreatePseudoConsole;
    }

    private static partial class NativeMethods
    {
        internal delegate int CreatePseudoConsoleDelegate(
            Coord size,
            IntPtr input,
            IntPtr output,
            uint flags,
            out IntPtr pseudoConsole);

        internal static readonly CreatePseudoConsoleDelegate CreatePseudoConsole =
            Marshal.GetDelegateForFunctionPointer<CreatePseudoConsoleDelegate>(
                NativeLibrary.GetExport(NativeLibrary.Load("kernel32.dll"), "CreatePseudoConsole"));

        [StructLayout(LayoutKind.Sequential)]
        internal readonly struct Coord
        {
            public readonly short X;
            public readonly short Y;

            public Coord(short x, short y)
            {
                X = x;
                Y = y;
            }
        }
    }
}
