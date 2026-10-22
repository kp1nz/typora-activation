# Typora 1.2.4 — 逆向分析 + 离线激活 + 遥测关闭

目标：`C:\Program Files\Typora\Typora.exe`（安装包版本 `17.1.2`，应用版本 `1.2.4`）
状态：**已激活** + **遥测已关闭** + **自动更新已关闭**
分析日期：2026-10-20

> 一句话总结：没有 patch 任何文件。加密的 `atom.js` 从进程内存里拿到明文后，
> 发现本构建把服务端校验换成了本地回显，并且重读授权时**只比对机器指纹**，
> 所以只要往注册表写一条自造的 `SLicense` 就激活了。

---

## 版本支持

| Typora 版本 | 授权模型 | 方案 | 入口 |
|---|---|---|---|
| 1.2.4 | 明文 `SLicense`，只比对指纹 | 注册表离线激活，纯 PowerShell | `activate.cmd` / `activate.ps1` |
| 1.12.3 | RSA 加密载荷 + `publicDecrypt` | 重建 `app.asar` 注入授权 shim | [`v1.12.3/`](v1.12.3/README.md) |

**1.12.3 起不能用根目录这套了**：`SLicense` 变成 `base64(RSA 密文)`，主进程用内置公钥解密后校验，
私钥在服务器侧，离线伪造走不通；而且试用到期后启动约 1.4 秒就会 `app.quit()` 自杀。
差异细节、shim 原理、部署与回滚见 [v1.12.3/README.md](v1.12.3/README.md)。

---

## 目录结构

```
C:\workbench\typora-1.2.4-activation\
├─ activate.cmd          ← 双击这个（一键激活）
├─ activate.ps1          一键激活本体（纯 PowerShell，免依赖）
├─ deactivate.ps1        撤销激活 / 恢复遥测
├─ README.md             本文件
├─ v1.12.3\              Typora 1.12.3 专用方案（asar 注入 + 授权 shim）
│   ├─ shim.js           注入主进程的授权 shim
│   ├─ build-asar.js     重建 app.asar（插 shim require + 重算 SHA-256）
│   ├─ deploy.ps1        备份 + 部署（自动提权）
│   ├─ restore.ps1       还原
│   └─ README.md         版本差异、原理、用法、验证
├─ license\              每次激活的记录 + 历史 SLicense
├─ source\
│   └─ atom_src.js       从内存 dump 出来的加密 atom.js 明文（350 KB / 6862 行）
├─ evidence\
│   └─ typora_window.png 激活后运行截图
└─ tools\
    ├─ keygen.js         Node 版 keygen（与 activate.ps1 等价，仅作对照）
    ├─ notel.js          Node 版遥测开关
    └─ analysis\         分析期用到的脚本（asar 解包 / 内存扫描 / 截图 等）
```

---

## 一键激活

**双击 `activate.cmd`** 即可。它会自动完成：

1. 关闭正在运行的 Typora（含强杀兜底）+ 清 `lockfile`
2. 读 `HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid`（64 位视图）
3. 算机器指纹 → 生成带正确校验位的授权码
4. 写 `HKCU\Software\Typora\SLicense`（REG_SZ）
5. 关遥测：`send_usage_info=false`、`enableAutoUpdate=false`
6. 用 **WMI `Win32_Process.Create`** 拉起 Typora（父进程是 `WmiPrvSE`，脚本窗口关掉也不会
   把应用带走；WMI 不可用时回退到 `explorer.exe`），读日志回显 `hasL: true/false` 做验证

命令行用法：

```powershell
.\activate.cmd                          # 默认
.\activate.cmd -Email me@example.com    # 自定义邮箱
.\activate.cmd -KeepTelemetry           # 不动遥测设置
.\activate.cmd -NoLaunch                # 只写授权，不启动
```

不需要 node / python / 任何第三方库，Windows PowerShell 5.1 和 PowerShell 7 都实测通过。

撤销：

```powershell
.\deactivate.ps1                    # 只清授权
.\deactivate.ps1 -RestoreTelemetry  # 顺便把遥测和自动更新打开
.\deactivate.ps1 -DeleteKey         # 直接删掉 HKCU\Software\Typora
```

---

## 1. 安装结构与保护

```
C:\Program Files\Typora\
├─ Typora.exe                        147 MB  Electron 主程序
└─ resources\
   ├─ app.asar                       467 KB  只有 3 个条目
   │   ├─ package.json               main = "main.node"
   │   ├─ atom.js                    467 KB  ← base64 后的密文（非明文）
   │   └─ main.node                  NAPI 壳加载器（在 app.asar.unpacked 里）
   ├─ lib.asar                       7 MB    前端库
   └─ node_modules.asar              11 MB
```

1. `atom.js`：字母表只有 64 个字符、无 `=` 填充、字节熵 6.0 → base64 包裹的密文。
   解码后 350,592 字节，正好是 16 的倍数（AES-CBC/ECB 特征）。
2. `main.node`（MZ, x64, 464 KB）是自研壳加载器：
   - `c:\users\leech\workspace\typemark64\launch\src\main.cpp`
   - 关键字符串：`./atom.js`、`app.asar`、`_compile`、`napi_run_script`、`__SHOW_ERROR_AND_QUIT__`、
     **`This program has been changed by others.`**（完整性校验）、`IsDebuggerPresent`（反调试）
   - **内部没有任何 `license/activ*` 字符串** → 授权逻辑不在壳里
3. 授权逻辑 100% 在加密的 `atom.js`（主进程）里；渲染进程 `appsrc/window/frame.js`
   只读 `File.option.hasLicense`。

### 绕过壳：内存取明文（不 patch 任何文件）

对运行中的主进程做 `ReadProcessMemory` 全量区域扫描，以 `hasLicense` 作特征，
在 `0x50c808400000` 起 2.28 MB 私有 RW 区里找到 **UTF-16 存的明文源码**，
自偏移 `790699` 起连续 350,371 字符 = 完整 `atom.js`（→ `source\atom_src.js`）。

> 附带发现：本分发版把服务端校验整段替换成了本地回显
> （`var o = {data:{code:0,msg:...}}`），`addLicense` 根本不发网络请求。

---

## 2. 授权模型（还原自 atom.js）

### 机器指纹 `M()`

```js
fingerprint = sha256(MachineGuid + "typora").digest("base64")
                .substr(0, 10)
                .replace(/[/=+-]/g, "a")
```

本机 MachineGuid 和指纹属于环境数据，公开仓库不包含实际值。

### 授权码格式 `Y()`

```
XXXXXX-XXXXXX-XXXXXX-XXXXXX      24 字符，4 组
字母表: L23456789ABCDEFGHJKMNPQRSTUVWXYZ   (32 个，去掉了 0 O 1 I)
校验位: 第 22、23 位
  for n in 0..1:
      o = Σ alphabet.indexOf(code[n + i])   for i = 0,2,4,...,14
      o %= 32
      checksum += alphabet[o]
```

### 存储与生效链

| 环节 | 实现 |
|---|---|
| 存储（Win） | 注册表 `HKCU\Software\Typora`，值名 **`SLicense`**（REG_SZ） |
| 值格式 | `base64(JSON{fingerprint,email,license,type}) + "#0#" + toLocaleDateString("en-US")` |
| 读取 | `_()`：按 `#` 切分 → base64 解 → `JSON.parse` → **只比对 `fingerprint == M()`** |
| 生效 | 启动时 `startL()` → `j()` → `H(email, license, type)` → `s = true` → `hasLicense` |
| 未激活 | 左下角 DOM 注入 `UNREGISTERED ×` 徽标 + 每 2~4 小时弹 `page-dist/license.html` |

关键：`SLicense` 里的 `license` 字段**重读时不再跑 `Y()` 校验**，只比对指纹 →
自造一条格式合法、校验位正确的码即可。

---

## 3. 遥测 / 自动更新

两条上报链路，由**同一个设置**控制：`send_usage_info`。

| 链路 | 位置 | 内容 | 门禁 |
|---|---|---|---|
| Sentry（Raven） | 主进程，DSN `41af752e…@sentry.typora.io/2` | 未捕获异常、崩溃、`instance`/`arch`/`appVersion`，还把 `hasLicense` 当 tag 发 | `shouldSendCallback` 里 `get("send_usage_info") != "false"` |
| AWS Pinpoint | 渲染进程 `us-west-2`，硬编码 Cognito IdentityPool `us-west-2:146e5a95-…5b32fc3280b` | 行为事件 `launch` / `newInstall` / `upgradeApp` / `openFile` / `QuickOpen` / `newWindow`… | `var a=()=>File.option.sendAnonymousUsage`，`install()` 里 `if(a())` 才加载 `aws-sdk.min.js` |

设置文件：`%APPDATA%\Typora\profile.data`，格式 `hex(JSON)`（见 `W()` 的
`serialize: Buffer.from(str).toString("hex")`）。

原状：`send_usage_info` **键不存在** → 默认 `true` → 两条链路一直是开的。
现在：`false`（Raven 与 Pinpoint 同时失效）；`enableAutoUpdate=false`（
防止升级后重新引入服务端校验、把激活冲掉）。

---

## 4. 验证

日志 `%APPDATA%\Typora\typora.log`：

```
INFO 2026/10/20 20:05:14  start LM in devVersion=false
INFO 2026/10/20 20:05:14  [watch L] hasL: true        ← 之前一直是 false
```

清 DNS 缓存后冷启动：

```
Typora 进程      : 6
外连（非本地）    : 无任何外连
DNS 缓存命中      : 无（sentry / pinpoint / amazonaws / cognito / typora.io 全无）
授权状态          : hasL: true
```

进程内存里 `"hasLicense":true`、`"sendAnonymousUsage":false` 均可查到（主进程 + 各渲染进程）；
因为 `install()` 提前返回，`aws-sdk.min.js` 根本不会被加载。

---

## 5. 排坑

- **从受限 shell 里 `Start-Process Typora.exe` 会瞬间退出（exit 0、日志一行不写）**：
  该 shell 环境里同时存在 `NO_PROXY` 和 `no_proxy` 两个键，Electron 起不来。
  正常从开始菜单 / 资源管理器启动没问题 —— 脚本里就是经 `explorer.exe` 拉起的。
- 强杀后 `%APPDATA%\Typora\lockfile` 可能残留，脚本会自动删。
- **别用 `Start-Process explorer.exe ...` 启动后就让脚本退出**：Typora 可能成了它的子进程，
  脚本树的收尾会把它一起带走（日志里表现为优雅的 `before-quit`）。所以脚本用 WMI 创建进程。
- `[L] installDate is 1/1/1970, trail remains: 0 days` 是 `IDate` 缺失导致的试用到期提示，
  激活后不影响（`s=true` 直接跳过试用判定）。
- 脚本用 UTF-8 **带 BOM** 保存，否则 Windows PowerShell 5.1 会把中文读成乱码
  （`.cmd` 用 `-File` 调起，BOM 丢了就会出现 "意外的标记" 解析错误）。

---

## 6. 迁移 / 复用

- **换机器或重装**：重跑 `activate.cmd`。指纹跟 `MachineGuid` 走，会自动变。
- **卸载**：`deactivate.ps1`（加 `-RestoreTelemetry` 一并恢复上报）。
- **想彻底断掉历史数据关联**：`profile.data` 里的 `uuid` 是历史匿名 ID，换掉即可
  （副作用：本地历史/最近文档统计重置）。

## 7. 免责

仅用于本地研究与个人环境恢复可用状态。所有操作都可逆：授权=一条注册表值，
遥测=设置里两个布尔键。请自行确认所在地区关于软件许可的法律要求。


## 8. 许可证

原创脚本和文档使用 MIT 许可证，见 LICENSE.md。提取的 Typora 第三方源码不在 MIT 授权范围内，详见 NOTICE。机器相关的 license/ 记录和 evidence/ 截图仅保留在本地，不提交到仓库。


