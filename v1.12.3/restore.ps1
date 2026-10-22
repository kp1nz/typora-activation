<#
.SYNOPSIS
    还原 Typora 1.12.3 的原始状态（撤销授权 shim）。

.DESCRIPTION
    1. 关闭 Typora
    2. 用 resources\app.asar.orig-backup 恢复原始 app.asar
    3. 删除 %LOCALAPPDATA%\TyporaPatch（shim 与日志）
    4. 可选删除 HKCU\Software\Typora 下的 SLicense 值（-RemoveSLicense）

    需要管理员权限：脚本会自动通过 UAC 自我提权。

.EXAMPLE
    .\restore.ps1
    .\restore.ps1 -RemoveSLicense
#>
[CmdletBinding()]
param(
    [string]$TyporaRoot = '',
    [switch]$RemoveSLicense
)

$ErrorActionPreference = 'Stop'

function Write-Step($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Write-Bad($m)  { Write-Host "[x] $m" -ForegroundColor Red }

# ---------------------------------------------------------------- elevate
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "需要管理员权限，正在请求提权..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($TyporaRoot)    { $argList += @('-TyporaRoot', "`"$TyporaRoot`"") }
    if ($RemoveSLicense) { $argList += '-RemoveSLicense' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait
    exit
}

# ---------------------------------------------------------------- locate Typora
if (-not $TyporaRoot) {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Typora'),
        (Join-Path ${env:ProgramFiles(x86)} 'Typora'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Typora')
    ) | Where-Object { $_ -and (Test-Path (Join-Path $_ 'Typora.exe')) }
    if (-not $candidates) { Write-Bad "找不到 Typora 安装目录，请用 -TyporaRoot 指定"; exit 1 }
    $TyporaRoot = $candidates[0]
}
$ResDir  = Join-Path $TyporaRoot 'resources'
$Target  = Join-Path $ResDir 'app.asar'
$Backup  = Join-Path $ResDir 'app.asar.orig-backup'
$PatchDir = Join-Path $env:LOCALAPPDATA 'TyporaPatch'

Write-Step "Typora: $TyporaRoot"

# ---------------------------------------------------------------- stop app
$procs = @(Get-Process Typora -ErrorAction SilentlyContinue)
if ($procs.Count -gt 0) {
    Write-Step "关闭 Typora（$($procs.Count) 个进程）..."
    foreach ($p in $procs) { try { $p.CloseMainWindow() | Out-Null } catch {} }
    Start-Sleep -Seconds 3
    Get-Process Typora -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
Remove-Item (Join-Path $env:APPDATA 'Typora\lockfile') -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- restore asar
if (-not (Test-Path $Backup)) {
    Write-Bad "找不到原始备份: $Backup"
    Write-Bad "可从安装包重新解出 resources\app.asar 后放到该路径"
    exit 1
}

Copy-Item $Backup $Target -Force
$h = (Get-FileHash $Target -Algorithm SHA256).Hash
Write-Ok "已恢复 app.asar ($((Get-Item $Target).Length) 字节)"
Write-Host "    sha256: $h" -ForegroundColor DarkGray

# ---------------------------------------------------------------- remove shim
if (Test-Path $PatchDir) {
    Remove-Item $PatchDir -Recurse -Force
    Write-Ok "已删除 shim 目录: $PatchDir"
} else {
    Write-Step "shim 目录不存在，跳过"
}

# ---------------------------------------------------------------- registry
if ($RemoveSLicense) {
    Remove-ItemProperty -Path 'HKCU:\Software\Typora' -Name 'SLicense' -Force -ErrorAction SilentlyContinue
    Write-Ok "已删除 HKCU\Software\Typora\SLicense"
}

Write-Host ""
Write-Ok "还原完成。重新启动 Typora 即为未修改版本。"
