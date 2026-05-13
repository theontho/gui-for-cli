using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace GUIForCLIWindows.Core;

public sealed class WindowsJobObject : IDisposable
{
    private IntPtr _handle;

    private WindowsJobObject(IntPtr handle)
    {
        _handle = handle;
    }

    public static bool IsSupported => OperatingSystem.IsWindows();

    public static WindowsJobObject? TryCreateKillOnClose()
    {
        if (!IsSupported)
        {
            return null;
        }

        var handle = NativeMethods.CreateJobObjectW(IntPtr.Zero, null);
        if (handle == IntPtr.Zero)
        {
            return null;
        }

        var job = new WindowsJobObject(handle);
        try
        {
            job.SetKillOnClose();
            return job;
        }
        catch
        {
            job.Dispose();
            return null;
        }
    }

    public bool TryAssign(Process process)
    {
        if (_handle == IntPtr.Zero)
        {
            return false;
        }

        return NativeMethods.AssignProcessToJobObject(_handle, process.Handle);
    }

    public void Dispose()
    {
        if (_handle != IntPtr.Zero)
        {
            NativeMethods.CloseHandle(_handle);
            _handle = IntPtr.Zero;
        }
    }

    private void SetKillOnClose()
    {
        var info = new NativeMethods.JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            BasicLimitInformation = new NativeMethods.JOBOBJECT_BASIC_LIMIT_INFORMATION
            {
                LimitFlags = NativeMethods.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
            },
        };

        var length = Marshal.SizeOf<NativeMethods.JOBOBJECT_EXTENDED_LIMIT_INFORMATION>();
        var buffer = Marshal.AllocHGlobal(length);
        try
        {
            Marshal.StructureToPtr(info, buffer, fDeleteOld: false);
            if (!NativeMethods.SetInformationJobObject(
                _handle,
                NativeMethods.JobObjectInfoType.ExtendedLimitInformation,
                buffer,
                (uint)length))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static partial class NativeMethods
    {
        internal const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        internal static extern IntPtr CreateJobObjectW(IntPtr lpJobAttributes, string? lpName);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetInformationJobObject(
            IntPtr hJob,
            JobObjectInfoType jobObjectInfoClass,
            IntPtr lpJobObjectInfo,
            uint cbJobObjectInfoLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CloseHandle(IntPtr hObject);

        internal enum JobObjectInfoType
        {
            ExtendedLimitInformation = 9,
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct IO_COUNTERS
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public nuint MinimumWorkingSetSize;
            public nuint MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public nuint Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public nuint ProcessMemoryLimit;
            public nuint JobMemoryLimit;
            public nuint PeakProcessMemoryUsed;
            public nuint PeakJobMemoryUsed;
        }
    }
}
