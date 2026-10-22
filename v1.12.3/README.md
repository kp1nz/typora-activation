# Typora 1.12.3 — 授权模型变化与本地 shim

> 目标：`C:\Program Files\Typora\Typora.exe`（应用版本 **1.12.3**，Electron 35.6.0 / Node 22.15.1）
> 状态：本地 `hasL: true`，无 `UNREGISTERED` 徽标，试用到期不再触发启动自杀
> 分析日期：2026-10-22

**根目录那套 `activate.ps1`（写一条 24 位 `SLicense` 就激活）只对 1.2.4 有效。**
1.12.3 把授权载荷改成了 RSA 加密块，离线伪造密钥这条路走不通。本目录是 1.12.3 专用的替代方案。

---

## 1. 和 1.2.4 到底哪里不一样

| 环节 | 1.2.4（根目录方案） | 1.12.3（本目录） |
|---|---|---|
| 主进程代码 | 加密的 `atom.js`，可从内存 dump 出明文 | `atom.compiled.dist.jsc`，V8 bytecode，无明文源码 |
| `SLicense` 值 | `base64(JSON)#0#date`，JSON 明文 | `base64(<RSA 密文>)#0#date` |
| 校验 | 只比对 `fingerprint == M()` | `crypto.publicDecrypt(内置公钥, 载荷)`，解密结果再校验 |
| 直接套用 1.2.4 的结果 | 激活成功 | `RSA routines:OPENSSL_internal:DATA_LEN_NOT_EQUAL_TO_MOD_LEN` → `hasL: false` |
| 试用到期行为 | 弹窗提醒，仍可用 | **启动约 1.4 秒后 `app.quit()` 退出** |

实测日志（把 1.2.4 脚本生成的 24 位码写进注册表后启动 1.12.3）：

```
DEBUG  [WindowsLicenseLocalStore] SLicense : eyJmaW5nZXJwcmludCI6...
ERROR  error error:04000070:RSA routines:OPENSSL_internal:DATA_LEN_NOT_EQUAL_TO_MOD_LEN
INFO   no info
DEBUG  onUnfillLicense
INFO   [watch L] hasL: false
ERROR  [LC] l
ERROR  Integrity check failed
```

私钥只在 Typora 服务器侧，所以**不能靠伪造 SLicense 离线激活**。

---

## 2. 方案：控制解密结果，而不是伪造密文

`resources/app.asar` 里只有三个条目，其中 `launch.dist.js`（1.3 KB）是**明文**的 bytenode 加载器：

```js
"use strict";const fs=require("fs"),path=require("path"),vm=require("vm"),v8=require("v8"),Module=require("module");
...Module._extensions[".jsc"]=...;require("./atom.compiled.dist.jsc");
```

在它前面插一行 `require(<shim>)`，shim 就运行在主进程最早的时机，可以做四件事：

1. **写合规 SLicense** —— 启动时刷新 `HKCU\Software\Typora\SLicense`，格式为
   `base64({fingerprint,email,license,type}) + "#0#" + M/d/yyyy`，
   `license` 为 24 位 `XXXXXX-XXXXXX-XXXXXX-XXXXXX`（字母表 `L23456789ABCDEFGHJKMNPQRSTUVWXYZ`，第 22/23 位校验）。
   保证主进程读到的是内容而不是空值。
2. **接管 `crypto.publicDecrypt`** —— 真实解密失败时返回携带本机指纹的授权 JSON。
   主进程据此走 `[L] pass` 分支 → `hasL: true`。这是核心一步。
3. **抑制试用到期的自杀** —— 只拦来自定时器 `atom.compiled.dist.jsc:1:76238` 的 `app.quit()`
   以及启动 15 秒内的调用；用户自己关窗口 / 菜单退出仍然正常（日志会完整出现 `before-quit → will-quit → quit`）。
4. **伪装渲染层** —— 主进程会往页面注入 `File.option.hasLicense = false` 并创建 `UNREGISTERED` 徽标，
   shim 把这段脚本改写为 `hasLicense = true` 且不建徽标；启动时那个「试用 0 天到期」的 license 弹窗
   先隐藏、等编辑窗口就绪后再回收。

### 已确认的实现细节（便于复查）

- **机器指纹**（与 1.2.4 相同）
  `fp = base64(sha256(MachineGuid + "typora"))[0..9]`，再把 `[/=+-]` 替换成 `a`
- **授权码格式** `/^([A-Z0-9]{6}-){3}[A-Z0-9]{6}$/`，字母表 `L23456789ABCDEFGHJKMNPQRSTUVWXYZ`
- **校验位** 第 22/23 位 = 对 `body[n + i] (i = 0,2,…,14)` 的字母表下标求和后 `% 32`
- **machineCode IPC** 返回 `base64({"v":"win|1.12.3","i":"<fp>","l":"<HOSTNAME> | <USER> | Windows"})`
- **Electron fuse**（`Typora.exe` 内）
  | fuse | 值 | 影响 |
  |---|---|---|
  | `EnableEmbeddedAsarIntegrityValidation` | `0` | 改 asar 不会被拒 |
  | `OnlyLoadAppFromAsar` | `1` | 必须从 asar 加载，不能外置 |
  | `EnableNodeCliInspectArguments` | `0` | `--inspect` 无效 |
  | `EnableNodeOptionsEnvironmentVariable` | `1` | `NODE_OPTIONS` 仍会被 Electron 过滤，`--require` 注入不生效 |
  | `RunAsNode` | `0` | 不能用 `ELECTRON_RUN_AS_NODE` 复用它当 Node |

---

## 3. 用法

### 3.1 前置

- Node.js（仅用于重建 asar 容器，不需要第三方依赖）
- Windows PowerShell 5.1 或 PowerShell 7
- 一份**未被修改**的 `app.asar`：安装包里的，或首次 `deploy.ps1` 自动生成的 `app.asar.orig-backup`

### 3.2 三步

```powershell
# 1) 从原始 asar 生成注入版（输出 app.asar.patched）
node build-asar.js "C:\Program Files\Typora\resources\app.asar.orig-backup"

# 2) 部署（自动请求 UAC：备份原文件 → 替换 asar → 装 shim 到 %LOCALAPPDATA%\TyporaPatch）
.\deploy.ps1 -Asar .\app.asar.patched

# 3) 启动 Typora，验证
Select-String "$env:APPDATA\Typora\typora.log" -Pattern 'hasL' | Select-Object -Last 2
```

首次部署时如果 `app.asar` 还是原版，`build-asar.js` 也可以直接读它：

```powershell
node build-asar.js "C:\Program Files\Typora\resources\app.asar"
```

`build-asar.js` 会拒绝处理「已经打过 shim」的 asar，避免重复注入。

### 3.3 目录布局

```
v1.12.3\
├─ shim.js          注入主进程的授权 shim（部署时复制为 %LOCALAPPDATA%\TyporaPatch\hook.js）
├─ build-asar.js    重建 app.asar（插 require + 重算 header SHA-256）
├─ deploy.ps1       备份 + 替换 asar + 安装 shim（自动提权）
└─ restore.ps1      还原原始 asar + 删除 shim（自动提权）
```

运行时产物：

| 路径 | 说明 |
|---|---|
| `resources\app.asar` | 注入版 |
| `resources\app.asar.orig-backup` | 原始文件备份（首次部署生成） |
| `%LOCALAPPDATA%\TyporaPatch\hook.js` | shim 本体 |
| `%LOCALAPPDATA%\TyporaPatch\hook.log` | shim 运行日志 |
| `HKCU\Software\Typora\SLicense` | 每次启动由 shim 重写 |

---

## 4. 验证

```
DEBUG 2026/10/22 15:57:30  376  [L] pass
INFO  2026/10/22 15:57:30  470  [watch L] hasL: true
```

shim 日志（`%LOCALAPPDATA%\TyporaPatch\hook.log`）在正常启动时大致是：

```
--- shim loaded pid=...
SLicense refreshed: XXXXXX-XXXXXX-XXXXXX-XXXXXX
publicDecrypt fallback -> local payload
quit suppressed (age=1304 trialGuard=true)
badge script rewritten
hiding trial popup
disposing hidden trial popup
```

界面侧：主窗口左下角**没有** `UNREGISTERED ×` 徽标，也没有「您的试用还有 0 天到期」弹窗。

日志里这两条是正常的、无害的：

- `[renewL]: unfill due to renew fail` —— 联网续期连不上 `typoraio.cn`，之后会用本地授权继续，`hasL` 保持 `true`
- `[LC] l` / `Integrity check failed` —— license 页面自身的检查，不影响主进程状态

---

## 5. 回滚

```powershell
.\restore.ps1                  # 恢复 app.asar + 删除 shim
.\restore.ps1 -RemoveSLicense  # 顺便删掉 HKCU\Software\Typora\SLicense
```

手动等价操作：

```powershell
Copy-Item "C:\Program Files\Typora\resources\app.asar.orig-backup" `
          "C:\Program Files\Typora\resources\app.asar" -Force
Remove-Item "$env:LOCALAPPDATA\TyporaPatch" -Recurse -Force
```

---

## 6. 限制与注意

- **Typora 升级会覆盖 `app.asar`**，shim 随之失效（表现为未激活 + 启动自杀）。
  升级后重跑 `build-asar.js` + `deploy.ps1` 即可；注意新版 `atom.compiled.dist.jsc` 的偏移（`76238`）会变，
  如果试用兜底那行不再触发抑制，用 15 秒时间窗的兜底逻辑仍然生效。
- shim 每次启动都会重写 `SLicense`，所以「移除许可证」在下次启动后会被覆盖。
- `license` 字段里的邮箱与标识都是本地伪造值（`local@typora.local` / `TYPO-LCS-LOCAL-2026`），
  可在 `shim.js` 顶部的 `EMAIL`、`LMARK` 修改。
- 这是**本地状态注入**，不是拿到 Typora 的合法授权；`帮助 → 我的许可证` 里看到的信息由本地 shim 提供。
- 仅用于本机研究与个人环境恢复可用状态，所有改动均可逆。

---

## 7. 与 1.2.4 方案的关系

两套方案互不依赖：

- 1.2.4：根目录 `activate.ps1` / `activate.cmd`，纯注册表，无需改文件
- 1.12.3：本目录，需要重建并替换 `app.asar`

判断版本：`(Get-Item 'C:\Program Files\Typora\Typora.exe').VersionInfo.ProductVersion`。
`app.asar` 里存在 `launch.dist.js` 即为 1.12.x 及以后的布局。
