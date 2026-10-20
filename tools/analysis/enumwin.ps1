Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public class WinEnum {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    public static List<string> List(uint[] pids) {
        var res = new List<string>();
        EnumWindows((h, l) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (Array.IndexOf(pids, pid) >= 0) {
                var sb = new StringBuilder(512);
                GetWindowTextW(h, sb, 512);
                RECT r; GetWindowRect(h, out r);
                res.Add(h.ToInt64() + "|" + pid + "|" + IsWindowVisible(h) + "|" + IsIconic(h) + "|" + (r.Right-r.Left) + "x" + (r.Bottom-r.Top) + "|" + sb.ToString());
            }
            return true;
        }, IntPtr.Zero);
        return res;
    }
}
"@
$pids = (Get-Process -Name Typora).Id
Write-Host ("pids: " + ($pids -join ","))
$list = [WinEnum]::List([uint[]]$pids)
$list | ForEach-Object { Write-Host $_ }
