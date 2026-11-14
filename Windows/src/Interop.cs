using System;
using System.Runtime.InteropServices;
using System.Text;

namespace AudioMixer
{
    // ---- Core Audio (MMDevice / WASAPI session) COM interfaces ----

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorCom { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int Item(int index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object instance);
        [PreserveSig] int OpenPropertyStore(int access, out IPropertyStore store);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out int state);
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyStore
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetAt(int index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PropertyKey
    {
        public Guid FmtId;
        public int Pid;
    }

    /// Only the string case is read; the layout covers both 32- and 64-bit sizes.
    [StructLayout(LayoutKind.Explicit, Size = 24)]
    internal struct PropVariant
    {
        [FieldOffset(0)] public ushort Vt;
        [FieldOffset(8)] public IntPtr Pointer;
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionManager2
    {
        [PreserveSig] int GetAudioSessionControl(IntPtr sessionGuid, int flags, out IntPtr control);
        [PreserveSig] int GetSimpleAudioVolume(IntPtr sessionGuid, int flags, out IntPtr volume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator enumerator);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionEnumerator
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetSession(int index, out IAudioSessionControl2 session);
    }

    [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioSessionControl2
    {
        // IAudioSessionControl
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name, ref Guid context);
        [PreserveSig] int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
        [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path, ref Guid context);
        [PreserveSig] int GetGroupingParam(out Guid param);
        [PreserveSig] int SetGroupingParam(ref Guid param, ref Guid context);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
        // IAudioSessionControl2
        [PreserveSig] int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetProcessId(out uint pid);
        [PreserveSig] int IsSystemSoundsSession();
        [PreserveSig] int SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool optOut);
    }

    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface ISimpleAudioVolume
    {
        [PreserveSig] int SetMasterVolume(float level, ref Guid context);
        [PreserveSig] int GetMasterVolume(out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioMeterInformation
    {
        [PreserveSig] int GetPeakValue(out float peak);
    }

    // ---- Undocumented: system default endpoint (same call the Sound control panel makes) ----

    [ComImport, Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9")]
    internal class PolicyConfigClientCom { }

    [ComImport, Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPolicyConfig
    {
        [PreserveSig] int GetMixFormat();
        [PreserveSig] int GetDeviceFormat();
        [PreserveSig] int ResetDeviceFormat();
        [PreserveSig] int SetDeviceFormat();
        [PreserveSig] int GetProcessingPeriod();
        [PreserveSig] int SetProcessingPeriod();
        [PreserveSig] int GetShareMode();
        [PreserveSig] int SetShareMode();
        [PreserveSig] int GetPropertyValue();
        [PreserveSig] int SetPropertyValue();
        [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string deviceId, int role);
    }

    /// Per-app output device, the mechanism behind Settings > System > Sound > Volume mixer.
    /// The WinRT factory "Windows.Media.Internal.AudioPolicyConfig" is undocumented, so it is
    /// called through its vtable rather than through a marshalled interface.
    internal sealed class AudioPolicyConfig
    {
        private const string RenderPrefix = @"\\?\SWD#MMDEVAPI#";
        private const string RenderSuffix = "#{e6327cad-dcec-4949-ae8a-991e976a79d2}";
        // IUnknown (3) + IInspectable (3) + 19 unrelated methods come first.
        private const int SlotSetPersisted = 25;
        private const int SlotGetPersisted = 26;
        private const int SlotClearAll = 27;

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int SetPersistedFn(IntPtr self, uint pid, int flow, int role, IntPtr deviceId);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetPersistedFn(IntPtr self, uint pid, int flow, int role, out IntPtr deviceId);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int ClearAllFn(IntPtr self);

        private readonly IntPtr factory;
        private readonly SetPersistedFn setPersisted;
        private readonly GetPersistedFn getPersisted;
        private readonly ClearAllFn clearAll;

        public string Variant { get; private set; }

        private AudioPolicyConfig(IntPtr factory, string variant)
        {
            this.factory = factory;
            Variant = variant;
            IntPtr vtable = Marshal.ReadIntPtr(factory);
            setPersisted = (SetPersistedFn)Marshal.GetDelegateForFunctionPointer(
                Marshal.ReadIntPtr(vtable, SlotSetPersisted * IntPtr.Size), typeof(SetPersistedFn));
            getPersisted = (GetPersistedFn)Marshal.GetDelegateForFunctionPointer(
                Marshal.ReadIntPtr(vtable, SlotGetPersisted * IntPtr.Size), typeof(GetPersistedFn));
            clearAll = (ClearAllFn)Marshal.GetDelegateForFunctionPointer(
                Marshal.ReadIntPtr(vtable, SlotClearAll * IntPtr.Size), typeof(ClearAllFn));
        }

        /// Returns null when this Windows build does not expose the interface.
        public static AudioPolicyConfig TryCreate(out string error)
        {
            error = null;
            IntPtr className;
            const string name = "Windows.Media.Internal.AudioPolicyConfig";
            int hr = Native.WindowsCreateString(name, name.Length, out className);
            if (hr < 0) { error = "WindowsCreateString 0x" + hr.ToString("X8"); return null; }
            try
            {
                // Windows 10 21H2 / Windows 11 first, then the older Windows 10 interface.
                string[] iids = { "ab3d4648-e242-459f-b02f-541c70306324", "2a59116d-6c4f-45e0-a74f-707e3fef9258" };
                foreach (string text in iids)
                {
                    Guid iid = new Guid(text);
                    IntPtr instance;
                    hr = Native.RoGetActivationFactory(className, ref iid, out instance);
                    if (hr >= 0 && instance != IntPtr.Zero) return new AudioPolicyConfig(instance, text);
                }
                error = "RoGetActivationFactory 0x" + hr.ToString("X8");
                return null;
            }
            catch (Exception ex)
            {
                error = ex.Message;
                return null;
            }
            finally
            {
                Native.WindowsDeleteString(className);
            }
        }

        /// deviceId is an MMDevice id; null or empty returns the app to the system default.
        public int SetOutput(uint pid, string deviceId)
        {
            IntPtr value = IntPtr.Zero;
            if (!string.IsNullOrEmpty(deviceId))
            {
                string packed = RenderPrefix + deviceId + RenderSuffix;
                int hr = Native.WindowsCreateString(packed, packed.Length, out value);
                if (hr < 0) return hr;
            }
            try
            {
                int console = setPersisted(factory, pid, 0, 0, value);     // eRender, eConsole
                int multimedia = setPersisted(factory, pid, 0, 1, value);  // eRender, eMultimedia
                return console < 0 ? console : multimedia;
            }
            finally
            {
                if (value != IntPtr.Zero) Native.WindowsDeleteString(value);
            }
        }

        /// The MMDevice id Windows has stored for this process, or "" for system default.
        public string GetOutput(uint pid)
        {
            IntPtr value;
            int hr = getPersisted(factory, pid, 0, 1, out value);
            if (hr < 0 || value == IntPtr.Zero) return "";
            try
            {
                uint length;
                IntPtr buffer = Native.WindowsGetStringRawBuffer(value, out length);
                string packed = buffer == IntPtr.Zero ? "" : Marshal.PtrToStringUni(buffer, (int)length);
                if (packed.StartsWith(RenderPrefix, StringComparison.OrdinalIgnoreCase)) packed = packed.Substring(RenderPrefix.Length);
                if (packed.EndsWith(RenderSuffix, StringComparison.OrdinalIgnoreCase)) packed = packed.Substring(0, packed.Length - RenderSuffix.Length);
                return packed;
            }
            finally
            {
                Native.WindowsDeleteString(value);
            }
        }

        public int ClearAll()
        {
            return clearAll(factory);
        }
    }

    internal static class Native
    {
        [DllImport("combase.dll", CharSet = CharSet.Unicode)]
        public static extern int WindowsCreateString([MarshalAs(UnmanagedType.LPWStr)] string source, int length, out IntPtr hstring);
        [DllImport("combase.dll")]
        public static extern int WindowsDeleteString(IntPtr hstring);
        [DllImport("combase.dll")]
        public static extern IntPtr WindowsGetStringRawBuffer(IntPtr hstring, out uint length);
        [DllImport("combase.dll")]
        public static extern int RoGetActivationFactory(IntPtr classId, ref Guid iid, out IntPtr factory);
        [DllImport("ole32.dll")]
        public static extern int PropVariantClear(ref PropVariant value);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(int access, bool inherit, uint pid);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder name, ref int size);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("user32.dll")]
        public static extern bool DestroyIcon(IntPtr icon);
        [DllImport("gdi32.dll")]
        public static extern bool DeleteObject(IntPtr handle);
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        public static extern int SHCreateItemFromParsingName(string path, IntPtr bindContext, ref Guid iid, out IShellItemImageFactory item);
        [DllImport("gdi32.dll")]
        public static extern int GetDIBits(IntPtr dc, IntPtr bitmap, int start, int lines, byte[] bits, ref BitmapInfoHeader info, int usage);
        [DllImport("user32.dll")]
        public static extern IntPtr GetDC(IntPtr hwnd);
        [DllImport("user32.dll")]
        public static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);

        public static string ProcessPath(uint pid)
        {
            IntPtr handle = OpenProcess(0x1000, false, pid);   // PROCESS_QUERY_LIMITED_INFORMATION
            if (handle == IntPtr.Zero) return null;
            try
            {
                StringBuilder buffer = new StringBuilder(1024);
                int size = buffer.Capacity;
                return QueryFullProcessImageName(handle, 0, buffer, ref size) ? buffer.ToString(0, size) : null;
            }
            finally
            {
                CloseHandle(handle);
            }
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeSize
    {
        public int Width;
        public int Height;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct BitmapInfoHeader
    {
        public int Size;
        public int Width;
        public int Height;
        public short Planes;
        public short BitCount;
        public int Compression;
        public int SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public int ClrUsed;
        public int ClrImportant;
    }

    [ComImport, Guid("BCC18B79-BA16-442F-80C4-8A59C30C463B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItemImageFactory
    {
        [PreserveSig] int GetImage(NativeSize size, int flags, out IntPtr bitmap);
    }
}
