Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class MemScan {
    public const int PROCESS_QUERY_INFORMATION = 0x0400;
    public const int PROCESS_VM_READ = 0x0010;
    public const uint MEM_COMMIT = 0x1000;
    public const uint PAGE_READWRITE = 0x04;
    public const uint PAGE_EXECUTE_READWRITE = 0x40;
    public const uint PAGE_READONLY = 0x02;
    public const uint PAGE_EXECUTE_READ = 0x20;
    public const uint PAGE_WRITECOPY = 0x08;
    public const uint PAGE_EXECUTE_WRITECOPY = 0x80;
    public const uint PAGE_GUARD = 0x100;
    public const uint PAGE_NOACCESS = 0x01;

    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION64 {
        public ulong BaseAddress;
        public ulong AllocationBase;
        public uint AllocationProtect;
        public uint __alignment1;
        public ulong RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
        public uint __alignment2;
    }

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(int access, bool inherit, int pid);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern int VirtualQueryEx(IntPtr hProcess, IntPtr lpAddress, out MEMORY_BASIC_INFORMATION64 lpBuffer, int dwLength);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, IntPtr nSize, out IntPtr lpNumberOfBytesRead);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);

    public static List<string> Scan(int pid, byte[] needle, int maxHits, int contextBytes) {
        var results = new List<string>();
        IntPtr h = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, pid);
        if (h == IntPtr.Zero) { results.Add("OPEN_FAIL:" + Marshal.GetLastWin32Error()); return results; }
        try {
            ulong addr = 0;
            int mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION64));
            long totalScanned = 0;
            while (true) {
                MEMORY_BASIC_INFORMATION64 mbi;
                if (VirtualQueryEx(h, (IntPtr)(long)addr, out mbi, mbiSize) == 0) break;
                ulong regionBase = mbi.BaseAddress;
                ulong regionSize = mbi.RegionSize;
                if (regionSize == 0) break;
                uint p = mbi.Protect;
                bool readable = (mbi.State == MEM_COMMIT)
                    && ((p & PAGE_GUARD) == 0)
                    && (p == PAGE_READWRITE || p == PAGE_READONLY || p == PAGE_EXECUTE_READ
                        || p == PAGE_EXECUTE_READWRITE || p == PAGE_WRITECOPY || p == PAGE_EXECUTE_WRITECOPY);
                if (readable && regionSize < (ulong)512 * 1024 * 1024) {
                    int size = (int)regionSize;
                    byte[] buf = new byte[size];
                    IntPtr read;
                    if (ReadProcessMemory(h, (IntPtr)(long)regionBase, buf, (IntPtr)size, out read) && (long)read > 0) {
                        int n = (int)read;
                        totalScanned += n;
                        int idx = 0;
                        while (idx <= n - needle.Length) {
                            int found = -1;
                            for (int i = idx; i <= n - needle.Length; i++) {
                                bool ok = true;
                                for (int j = 0; j < needle.Length; j++) { if (buf[i + j] != needle[j]) { ok = false; break; } }
                                if (ok) { found = i; break; }
                            }
                            if (found < 0) break;
                            int start = Math.Max(0, found - contextBytes);
                            int end = Math.Min(n, found + contextBytes);
                            byte[] seg = new byte[end - start];
                            Array.Copy(buf, start, seg, 0, seg.Length);
                            results.Add("ADDR:0x" + (regionBase + (ulong)found).ToString("x") + "|LEN:" + seg.Length + "|" + Convert.ToBase64String(seg));
                            if (results.Count >= maxHits) break;
                            idx = found + needle.Length;
                        }
                    }
                }
                if (results.Count >= maxHits) break;
                if (regionBase > (ulong)0x7FFFFFFF0000) break;
                ulong next = regionBase + regionSize;
                if (next <= addr) break;
                addr = next;
            }
            results.Add("SCANNED:" + totalScanned);
        } finally { CloseHandle(h); }
        return results;
    }
}
"@
Write-Host "MemScan type loaded"
