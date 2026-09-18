using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;

public class DisplayManager {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DISPLAY_DEVICE {
        [MarshalAs(UnmanagedType.U4)]
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        [MarshalAs(UnmanagedType.U4)]
        public DisplayDeviceStateFlags StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [Flags]
    public enum DisplayDeviceStateFlags : int {
        AttachedToDesktop = 0x1,
        MultiDriver = 0x2,
        PrimaryDevice = 0x4,
        MirroringDriver = 0x8,
        VGACompatible = 0x10,
        Removable = 0x20,
        ModesPruned = 0x8000000,
        Remote = 0x4000000,
        Disconnect = 0x2000000
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public ushort dmSpecVersion;
        public ushort dmDriverVersion;
        public ushort dmSize;
        public ushort dmDriverExtra;
        public uint dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public uint dmDisplayOrientation;
        public uint dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public ushort dmLogPixels;
        public uint dmBitsPerPel;
        public uint dmPelsWidth;
        public uint dmPelsHeight;
        public uint dmDisplayFlags;
        public uint dmDisplayFrequency;
        public uint dmICMMethod;
        public uint dmICMIntent;
        public uint dmMediaType;
        public uint dmDitherType;
        public uint dmReserved1;
        public uint dmReserved2;
        public uint dmPanningWidth;
        public uint dmPanningHeight;
    }

    public const int ENUM_CURRENT_SETTINGS = -1;
    public const uint CDS_UPDATEREGISTRY = 0x00000001;
    public const uint CDS_NORESET = 0x10000000;
    public const uint CDS_RESET = 0x40000000;

    public const uint DM_PELSWIDTH = 0x00080000;
    public const uint DM_PELSHEIGHT = 0x00100000;
    public const uint DM_DISPLAYFREQUENCY = 0x00400000;
    public const uint DM_BITSPERPEL = 0x00040000;

    public const int DISP_CHANGE_SUCCESSFUL = 0;
    public const uint DESKTOP_ALL_ACCESS = 0x01FF;

    public const int SM_CMONITORS = 80;
    public const uint SDC_APPLY = 0x00000080;
    public const uint SDC_TOPOLOGY_INTERNAL = 0x00000001;
    public const uint SDC_TOPOLOGY_EXTEND = 0x00000004;

    private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetDisplayConfig(
        uint numPathArrayElements,
        IntPtr pathArray,
        uint numModeInfoArrayElements,
        IntPtr modeInfoArray,
        uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr OpenDesktop(string lpszDesktop, uint dwFlags, bool fInherit, uint dwDesiredAccess);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetThreadDesktop(IntPtr hDesktop);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool CloseDesktop(IntPtr hDesktop);

    static DisplayManager() {
        // 高DPI環境（拡大率125%, 150%等）でも物理ピクセル解像度を正確に扱うためのDPI認識初期化
        try {
            SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        } catch { }
    }

    public static string GetPrimaryDeviceName() {
        DISPLAY_DEVICE d = new DISPLAY_DEVICE();
        for (uint id = 0; ; id++) {
            d.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            if (!EnumDisplayDevices(null, id, ref d, 0)) break;
            if ((d.StateFlags & DisplayDeviceStateFlags.MirroringDriver) != 0) continue;
            if ((d.StateFlags & DisplayDeviceStateFlags.PrimaryDevice) != 0) {
                return d.DeviceName;
            }
        }
        return @"\\.\DISPLAY1";
    }

    public static string GetSecondaryDeviceName() {
        DISPLAY_DEVICE d = new DISPLAY_DEVICE();
        // まずデスクトップに接続されている非プライマリディスプレイを検索
        for (uint id = 0; ; id++) {
            d.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            if (!EnumDisplayDevices(null, id, ref d, 0)) break;
            if ((d.StateFlags & DisplayDeviceStateFlags.MirroringDriver) != 0) continue;
            if ((d.StateFlags & DisplayDeviceStateFlags.AttachedToDesktop) != 0 && (d.StateFlags & DisplayDeviceStateFlags.PrimaryDevice) == 0) {
                return d.DeviceName;
            }
        }
        // 切断状態の場合は利用可能な非プライマリディスプレイアダプタを検索
        for (uint id = 0; ; id++) {
            d.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            if (!EnumDisplayDevices(null, id, ref d, 0)) break;
            if ((d.StateFlags & DisplayDeviceStateFlags.MirroringDriver) != 0) continue;
            if ((d.StateFlags & DisplayDeviceStateFlags.PrimaryDevice) == 0 && !string.IsNullOrEmpty(d.DeviceString)) {
                return d.DeviceName;
            }
        }
        return @"\\.\DISPLAY2";
    }

    public static bool HasSecondaryDevice() {
        DISPLAY_DEVICE d = new DISPLAY_DEVICE();
        for (uint id = 0; ; id++) {
            d.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            if (!EnumDisplayDevices(null, id, ref d, 0)) break;
            if ((d.StateFlags & DisplayDeviceStateFlags.MirroringDriver) != 0) continue;
            if ((d.StateFlags & DisplayDeviceStateFlags.PrimaryDevice) == 0 && !string.IsNullOrEmpty(d.DeviceString)) {
                return true;
            }
        }
        return false;
    }

    public static bool GetCurrentDisplayMode(string deviceName, out int width, out int height, out int frequency, out int bpp) {
        width = 0; height = 0; frequency = 0; bpp = 0;
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
        dm.dmDriverExtra = 0;
        if (EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref dm)) {
            width = (int)dm.dmPelsWidth;
            height = (int)dm.dmPelsHeight;
            frequency = (int)dm.dmDisplayFrequency;
            bpp = (int)dm.dmBitsPerPel;
            return true;
        }
        return false;
    }

    public static bool SetDisplayResolutionAndRate(string deviceName, int width, int height, int targetFrequency, out int appliedFrequency) {
        int resultFrequency = targetFrequency;
        bool isSuccess = false;

        IntPtr hDefaultDesk = OpenDesktop("Default", 0, false, DESKTOP_ALL_ACCESS);

        Thread worker = new Thread(() => {
            if (hDefaultDesk != IntPtr.Zero) {
                SetThreadDesktop(hDefaultDesk);
            }

            DEVMODE currentMode = new DEVMODE();
            currentMode.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
            currentMode.dmDriverExtra = 0;
            if (!EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref currentMode)) {
                currentMode.dmSize = 124;
                EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref currentMode);
            }

            DEVMODE targetMode = currentMode;
            DEVMODE enumMode = new DEVMODE();

            bool foundMode = false;
            int closestDiff = int.MaxValue;

            // 解像度が一致し、32-bitカラー深度かつリフレッシュレートが最も近い設定を優先検索
            for (int i = 0; ; i++) {
                enumMode.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
                enumMode.dmDriverExtra = 0;
                if (!EnumDisplaySettings(deviceName, i, ref enumMode)) break;

                if (enumMode.dmPelsWidth == width && enumMode.dmPelsHeight == height) {
                    int diff = Math.Abs((int)enumMode.dmDisplayFrequency - targetFrequency);
                    if (diff < closestDiff || (diff == closestDiff && enumMode.dmBitsPerPel > targetMode.dmBitsPerPel)) {
                        closestDiff = diff;
                        targetMode = enumMode;
                        foundMode = true;
                        if (diff == 0 && targetMode.dmBitsPerPel >= 32) break;
                    }
                }
            }

            if (foundMode) {
                resultFrequency = (int)targetMode.dmDisplayFrequency;
                if (targetMode.dmBitsPerPel < 32) {
                    targetMode.dmBitsPerPel = 32;
                }
            } else {
                targetMode.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
                targetMode.dmDriverExtra = 0;
                targetMode.dmPelsWidth = (uint)width;
                targetMode.dmPelsHeight = (uint)height;
                targetMode.dmDisplayFrequency = (uint)targetFrequency;
                targetMode.dmBitsPerPel = 32;
            }

            targetMode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY | DM_BITSPERPEL;

            int res = ChangeDisplaySettingsEx(deviceName, ref targetMode, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
            if (res != DISP_CHANGE_SUCCESSFUL) {
                res = ChangeDisplaySettingsEx(deviceName, ref targetMode, IntPtr.Zero, 0, IntPtr.Zero);
            }
            if (res != DISP_CHANGE_SUCCESSFUL) {
                // 特殊ドライバ向けフォールバック: カラー深度指定を除外し、解像度・周波数のみで適用
                targetMode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
                res = ChangeDisplaySettingsEx(deviceName, ref targetMode, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
                if (res != DISP_CHANGE_SUCCESSFUL) {
                    res = ChangeDisplaySettingsEx(deviceName, ref targetMode, IntPtr.Zero, 0, IntPtr.Zero);
                }
            }

            isSuccess = (res == DISP_CHANGE_SUCCESSFUL);
        });

        worker.IsBackground = true;
        worker.Start();
        if (!worker.Join(5000)) {
            try { worker.Abort(); } catch { }
        }

        if (hDefaultDesk != IntPtr.Zero) {
            CloseDesktop(hDefaultDesk);
        }

        appliedFrequency = resultFrequency;
        return isSuccess;
    }

    public static int GetMonitorCount() {
        return GetSystemMetrics(SM_CMONITORS);
    }

    private static string GetDisplaySwitchPath() {
        string sysDir = Environment.SystemDirectory;
        string fullPath = Path.Combine(sysDir, "DisplaySwitch.exe");
        if (File.Exists(fullPath)) return fullPath;
        return "DisplaySwitch.exe";
    }

    public static int LastCcdResult { get; private set; }

    private static int CallSetDisplayConfigOnDesktop(uint flags) {
        int result = -1;
        IntPtr hDefaultDesk = OpenDesktop("Default", 0, false, DESKTOP_ALL_ACCESS);
        Thread worker = new Thread(() => {
            if (hDefaultDesk != IntPtr.Zero) {
                SetThreadDesktop(hDefaultDesk);
            }
            result = SetDisplayConfig(0, IntPtr.Zero, 0, IntPtr.Zero, flags);
            LastCcdResult = result;
        });
        worker.IsBackground = true;
        worker.Start();
        if (!worker.Join(3000)) {
            try { worker.Abort(); } catch { }
        }
        if (hDefaultDesk != IntPtr.Zero) {
            CloseDesktop(hDefaultDesk);
        }
        return result;
    }

    private static void FallbackDisplaySwitch(string arg) {
        try {
            foreach (var p in Process.GetProcessesByName("DisplaySwitch")) {
                try { p.Kill(); } catch { }
            }
            var psi = new ProcessStartInfo(GetDisplaySwitchPath(), arg) {
                CreateNoWindow = true,
                UseShellExecute = false
            };
            using (var proc = Process.Start(psi)) {
                if (proc != null) proc.WaitForExit(2500);
            }
        } catch { }
    }

    public static bool SwitchTopologyInternal(int maxRetries = 3) {
        for (int attempt = 1; attempt <= maxRetries; attempt++) {
            int ret = CallSetDisplayConfigOnDesktop(SDC_APPLY | SDC_TOPOLOGY_INTERNAL);
            if (ret == 0) {
                for (int i = 0; i < 15; i++) {
                    if (GetMonitorCount() == 1) return true;
                    Thread.Sleep(100);
                }
            }
            FallbackDisplaySwitch("/internal");
            for (int i = 0; i < 10; i++) {
                if (GetMonitorCount() == 1) return true;
                Thread.Sleep(100);
            }
        }
        return (GetMonitorCount() == 1);
    }

    public static bool SwitchTopologyExtend(int maxRetries = 3) {
        for (int attempt = 1; attempt <= maxRetries; attempt++) {
            int ret = CallSetDisplayConfigOnDesktop(SDC_APPLY | SDC_TOPOLOGY_EXTEND);
            if (ret == 0) {
                for (int i = 0; i < 25; i++) {
                    if (GetMonitorCount() >= 2) return true;
                    Thread.Sleep(100);
                }
            }
            FallbackDisplaySwitch("/extend");
            for (int i = 0; i < 15; i++) {
                if (GetMonitorCount() >= 2) return true;
                Thread.Sleep(100);
            }
        }
        return (GetMonitorCount() >= 2);
    }
}
