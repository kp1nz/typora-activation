Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

public static class MemScan2 {
    public const int PROCESS_QUERY_INFORMATION = 0x0400;
    public const int PROCESS_VM_READ = 0x0010;
    public const uint MEM_COMMIT = 0x1000;
    public const uint PAGE_GUARD = 0x100;

    [StructLayout(LayoutKind.Sequential)]
    public struct MBI64 {
        public ulong BaseAddress;
        public ulong AllocationBase;
        public uint AllocationProtect;
        public uint a1;
        public ulong RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
        public uint a2;
    }

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern int VirtualQueryEx(IntPtr h, IntPtr addr, out MBI64 mbi, int len);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr h);

    static bool IsReadable(uint prot) {
        if ((prot & PAGE_GUARD) != 0) return false;
        uint p = prot & 0xff;
        return p == 0x02 || p == 0x04 || p == 0x08 || p == 0x20 || p == 0x40 || p == 0x80;
    }

    public static List<string> DumpRegions(int pid, byte[] needle, string outDir, int maxRegions, long maxRegionSize) {
        var log = new List<string>();
        IntPtr h = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, pid);
        if (h == IntPtr.Zero) { log.Add("OPEN_FAIL " + Marshal.GetLastWin32Error()); return log; }
        int found = 0;
        try {
            ulong addr = 0;
            int mbiSize = Marshal.SizeOf(typeof(MBI64));
            while (true) {
                MBI64 mbi;
                if (VirtualQueryEx(h, (IntPtr)(long)addr, out mbi, mbiSize) == 0) break;
                ulong baseAddr = mbi.BaseAddress;
                ulong size = mbi.RegionSize;
                if (size == 0) break;
                if (mbi.State == MEM_COMMIT && IsReadable(mbi.Protect) && size <= (ulong)maxRegionSize) {
                    int n = (int)size;
                    byte[] buf = new byte[n];
                    IntPtr rd;
                    if (ReadProcessMemory(h, (IntPtr)(long)baseAddr, buf, (IntPtr)n, out rd) && (long)rd > 0) {
                        n = (int)rd;
                        bool hit = false;
                        for (int i = 0; i <= n - needle.Length; i++) {
                            bool ok = true;
                            for (int j = 0; j < needle.Length; j++) { if (buf[i+j] != needle[j]) { ok = false; break; } }
                            if (ok) { hit = true; break; }
                        }
                        if (hit) {
                            string fn = Path.Combine(outDir, "region_" + pid.ToString() + "_" + baseAddr.ToString("x") + "_" + n.ToString() + ".bin");
                            File.WriteAllBytes(fn, buf);
                            log.Add("HIT 0x" + baseAddr.ToString("x") + " size=" + n + " prot=0x" + mbi.Protect.ToString("x") + " file=" + fn);
                            found++;
                        }
                    }
                }
                if (found >= maxRegions) break;
                if (baseAddr > (ulong)0x7FFFFFFF0000) break;
                ulong next = baseAddr + size;
                if (next <= addr) break;
                addr = next;
            }
        } finally { CloseHandle(h); }
        return log;
    }
}
"@
Write-Host "MemScan2 loaded"
