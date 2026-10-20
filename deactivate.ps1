<#
    撤销激活 / 恢复遥测
    ---------------------------------------------------------------
      .\deactivate.ps1                    # 只清授权
      .\deactivate.ps1 -RestoreTelemetry  # 顺便把遥测和自动更新打开
      .\deactivate.ps1 -DeleteKey         # 直接把 HKCU\Software\Typora 整个键删掉
#>
param(
    [switch]$RestoreTelemetry,
    [switch]$DeleteKey
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "=== Typora 撤销激活 ===" -ForegroundColor White

# 先关掉 Typora，否则退出时可能把值写回去
$procs = @(Get-Process -Name Typora -ErrorAction SilentlyContinue)
if ($procs.Count -gt 0) {
    Write-Host "[*] 关闭 Typora ..." -ForegroundColor Cyan
    foreach ($p in $procs) { try { $p.CloseMainWindow() | Out-Null } catch { } }
    Start-Sleep -Seconds 3
    $left = @(Get-Process -Name Typora -ErrorAction SilentlyContinue)
    if ($left.Count -gt 0) {
        foreach ($p in $left) { try { $p | Stop-Process -Force } catch { } }
        Start-Sleep -Seconds 2
    }
}

$hkcu = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', 'Default')
if ($DeleteKey) {
    $hkcu.DeleteSubKeyTree('Software\Typora', $false)
    Write-Host "[+] 已删除 HKCU\Software\Typora" -ForegroundColor Green
} else {
    $k = $hkcu.OpenSubKey('Software\Typora', $true)
    if ($k) {
        $k.SetValue('SLicense', '', [Microsoft.Win32.RegistryValueKind]::String)
        $k.Close()
        Write-Host "[+] SLicense 已清空" -ForegroundColor Green
    } else {
        Write-Host "[!] HKCU\Software\Typora 不存在，无需处理" -ForegroundColor Yellow
    }
}
$hkcu.Close()

if ($RestoreTelemetry) {
    $profile = Join-Path $env:APPDATA 'Typora\profile.data'
    if (Test-Path $profile) {
        $hexText = (Get-Content $profile -Raw).Trim()
        $raw = New-Object byte[] ($hexText.Length / 2)
        for ($i = 0; $i -lt $raw.Length; $i++) { $raw[$i] = [Convert]::ToByte($hexText.Substring($i * 2, 2), 16) }
        $cfg = [System.Text.Encoding]::UTF8.GetString($raw)
        $cfg = [regex]::Replace($cfg, '("send_usage_info"\s*:\s*)(true|false)', '${1}true')
        $cfg = [regex]::Replace($cfg, '("enableAutoUpdate"\s*:\s*)(true|false)', '${1}true')
        $outBytes = [System.Text.Encoding]::UTF8.GetBytes($cfg)
        $newHex = [BitConverter]::ToString($outBytes).Replace('-', '').ToLower()
        [System.IO.File]::WriteAllText($profile, $newHex, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "[+] 遥测 / 自动更新已恢复" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "完成。下次启动 Typora 即为未激活状态。" -ForegroundColor White
Write-Host ""
