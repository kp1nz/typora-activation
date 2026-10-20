<#
    Typora 一键激活（离线）
    ---------------------------------------------------------------
    免依赖：纯 PowerShell 实现，不需要 node / python / 任何第三方库。

    做法（逆向自 atom.js）：
      指纹   = base64(sha256(MachineGuid + "typora"))[0..9] , 把 / = + - 换成 a
      授权码 = 24 字符 6-6-6-6，字母表 L23456789ABCDEFGHJKMNPQRSTUVWXYZ
               第 22/23 位 = 前 16 位交错求和 mod 32
      落地   = HKCU\Software\Typora : SLicense
               base64({fingerprint,email,license,type}) + "#0#" + M/d/yyyy

    用法：
      .\activate.ps1                       # 激活 + 关遥测 + 拉起 Typora
      .\activate.ps1 -Email me@x.com       # 自定义邮箱
      .\activate.ps1 -KeepTelemetry        # 不动遥测设置
      .\activate.ps1 -NoLaunch             # 只写授权，不启动
    或直接双击 activate.cmd
#>
param(
    [string]$Email = "yg@typora.local",
    [switch]$KeepTelemetry,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$TyporaExe = 'C:\Program Files\Typora\Typora.exe'
$Alphabet  = 'L23456789ABCDEFGHJKMNPQRSTUVWXYZ'

function Write-Step($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Write-Note($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Bad($m)  { Write-Host "[x] $m" -ForegroundColor Red }

Write-Host ""
Write-Host "==================================================" -ForegroundColor White
Write-Host "     Typora 1.2.4  离线一键激活" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor White
Write-Host ""

if (-not (Test-Path $TyporaExe)) {
    Write-Bad "找不到 $TyporaExe ，请确认安装路径"
    exit 1
}

# ------------------------------------------------------------ 1. 关掉 Typora
$procs = @(Get-Process -Name Typora -ErrorAction SilentlyContinue)
if ($procs.Count -gt 0) {
    Write-Step "关闭正在运行的 Typora（$($procs.Count) 个进程）..."
    foreach ($p in $procs) { try { $p.CloseMainWindow() | Out-Null } catch { } }
    Start-Sleep -Seconds 3
    $left = @(Get-Process -Name Typora -ErrorAction SilentlyContinue)
    if ($left.Count -gt 0) {
        foreach ($p in $left) { try { $p | Stop-Process -Force } catch { } }
        Start-Sleep -Seconds 2
    }
    $still = @(Get-Process -Name Typora -ErrorAction SilentlyContinue)
    if ($still.Count -gt 0) { Write-Bad "无法关闭 Typora，请手动退出后重试"; exit 1 }
}
Remove-Item (Join-Path $env:APPDATA 'Typora\lockfile') -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------ 2. 机器指纹
Write-Step "读取 MachineGuid ..."
$guid = $null
try {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    $key = $base.OpenSubKey('SOFTWARE\Microsoft\Cryptography')
    $guid = $key.GetValue('MachineGuid')
    $key.Close(); $base.Close()
} catch { }
if (-not $guid) {
    $out = & reg query 'HKLM\SOFTWARE\Microsoft\Cryptography' /v MachineGuid /reg:64 2>$null
    foreach ($line in $out) { if ($line -match 'MachineGuid\s+REG_SZ\s+(\S+)') { $guid = $matches[1] } }
}
if (-not $guid) { Write-Bad "读取 MachineGuid 失败"; exit 1 }

$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($guid + 'typora'))
$fingerprint = [Convert]::ToBase64String($hash).Substring(0, 10) -replace '[/=+-]', 'a'
Write-Ok "MachineGuid  : $guid"
Write-Ok "fingerprint  : $fingerprint"

# ------------------------------------------------------------ 3. 授权码
function Get-Checksum([string]$body16) {
    $t = ''
    for ($n = 0; $n -lt 2; $n++) {
        $o = 0
        for ($i = 0; $i -lt 16; $i += 2) { $o += $Alphabet.IndexOf($body16[$n + $i]) }
        $o = $o % $Alphabet.Length
        $t += $Alphabet[$o]
    }
    return $t
}

$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$bytes = New-Object byte[] 22
$rng.GetBytes($bytes)
$body = ''
for ($i = 0; $i -lt 22; $i++) { $body += $Alphabet[$bytes[$i] % $Alphabet.Length] }
$full = $body + (Get-Checksum $body)
$license = ($full -replace '(.{6})', '$1-').TrimEnd('-')
Write-Ok "license code : $license"

# 自检：等价于 atom.js 里 Y()
$stripped = $license -replace '-', ''
$ok1 = ($stripped.Substring(22) -eq (Get-Checksum $stripped))
$ok2 = (($stripped -replace '[L23456789ABCDEFGHJKMNPQRSTUVWXYZ]', '').Length -eq 0)
if (-not ($ok1 -and $ok2)) { Write-Bad "授权码自检失败（不该发生）"; exit 1 }

# ------------------------------------------------------------ 4. 载荷
$obj = [ordered]@{
    fingerprint = $fingerprint
    email       = $Email
    license     = $license
    type        = ''
}
$json = ($obj | ConvertTo-Json -Compress) -replace '\s+', ''
$b64  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
$date = (Get-Date).ToString('M/d/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
$slicense = $b64 + '#0#' + $date
Write-Ok "email        : $Email"
Write-Ok "date         : $date"

# ------------------------------------------------------------ 5. 注册表
Write-Step "写入 HKCU\Software\Typora\SLicense ..."
$hkcu = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', 'Default')
$tk = $hkcu.CreateSubKey('Software\Typora')
$tk.SetValue('SLicense', $slicense, [Microsoft.Win32.RegistryValueKind]::String)
$tk.Close(); $hkcu.Close()
Write-Ok "已写入（REG_SZ, $($slicense.Length) 字符）"

$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$record = @(
    "time        : $stamp",
    "machine     : $env:COMPUTERNAME",
    "MachineGuid : $guid",
    "fingerprint : $fingerprint",
    "email       : $Email",
    "license     : $license",
    "SLicense    : $slicense"
) -join "`r`n"
$record | Set-Content (Join-Path $here "license\activation-$stamp.txt") -Encoding UTF8
Write-Ok "激活记录：license\activation-$stamp.txt"

# ------------------------------------------------------------ 6. 关遥测
if (-not $KeepTelemetry) {
    Write-Step "关闭遥测 / 自动更新 ..."
    $profile = Join-Path $env:APPDATA 'Typora\profile.data'
    if (Test-Path $profile) {
        $hexText = (Get-Content $profile -Raw).Trim()
        $raw = New-Object byte[] ($hexText.Length / 2)
        for ($i = 0; $i -lt $raw.Length; $i++) { $raw[$i] = [Convert]::ToByte($hexText.Substring($i * 2, 2), 16) }
        $cfg = [System.Text.Encoding]::UTF8.GetString($raw)
        Copy-Item $profile "$profile.bak-$stamp" -Force

        if ($cfg -match '"send_usage_info"\s*:\s*(true|false)') {
            $cfg = [regex]::Replace($cfg, '("send_usage_info"\s*:\s*)(true|false)', '${1}false')
        } else {
            $cfg = $cfg.TrimEnd()
            $cfg = $cfg.Substring(0, $cfg.Length - 1) + ',"send_usage_info":false}'
        }
        if ($cfg -match '"enableAutoUpdate"\s*:\s*(true|false)') {
            $cfg = [regex]::Replace($cfg, '("enableAutoUpdate"\s*:\s*)(true|false)', '${1}false')
        } else {
            $cfg = $cfg.TrimEnd()
            $cfg = $cfg.Substring(0, $cfg.Length - 1) + ',"enableAutoUpdate":false}'
        }

        $outBytes = [System.Text.Encoding]::UTF8.GetBytes($cfg)
        $newHex = [BitConverter]::ToString($outBytes).Replace('-', '').ToLower()
        [System.IO.File]::WriteAllText($profile, $newHex, (New-Object System.Text.UTF8Encoding($false)))
        Write-Ok "send_usage_info=false, enableAutoUpdate=false"
    } else {
        Write-Note "未找到 profile.data（首次启动后生成），跳过"
    }
}

# ------------------------------------------------------------ 7. 拉起并验证
if (-not $NoLaunch) {
    Write-Step "启动 Typora ..."
    # 用 WMI 创建进程：父进程是 WmiPrvSE，不挂在本脚本下，
    # 这样脚本窗口关掉 / 控制台退出 都不会把 Typora 一起带走。
    $launched = $false
    try {
        $res = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = ('"' + $TyporaExe + '"') }
        if ($res.ReturnValue -eq 0) { $launched = $true }
    } catch { }
    if (-not $launched) {
        try {
            $res2 = ([wmiclass]'Win32_Process').Create('"' + $TyporaExe + '"')
            if ($res2.ReturnValue -eq 0) { $launched = $true }
        } catch { }
    }
    if (-not $launched) {
        Write-Note "WMI 启动失败，回退到 explorer 启动"
        Start-Process explorer.exe -ArgumentList ('"' + $TyporaExe + '"') | Out-Null
    }
    Start-Sleep -Seconds 9

    $log = Join-Path $env:APPDATA 'Typora\typora.log'
    $line = $null
    if (Test-Path $log) {
        $line = Select-String -Path $log -Pattern 'hasL: (true|false)' -Encoding UTF8 | Select-Object -Last 1
    }
    Write-Host ""
    if ($line -and ($line.Line -match 'hasL: true')) {
        Write-Ok ("激活成功  ->  " + ($line.Line -replace '\s+', ' '))
    } elseif ($line) {
        Write-Note ("授权未生效 -> " + ($line.Line -replace '\s+', ' '))
        Write-Note "检查：是否还有其他 Typora 实例；或看 %APPDATA%\Typora\typora.log"
    } else {
        Write-Note "日志里没有 hasL 记录，请在 Typora 的 帮助 -> 我的许可证 里确认"
    }
} else {
    Write-Host ""
    Write-Ok "已写入授权（未启动 Typora）"
}

Write-Host ""
Write-Host "SLicense: $slicense" -ForegroundColor DarkGray
Write-Host ""
