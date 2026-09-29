# Termux + Shizuku 使用前置

本页只在**手机本机路线**（在 Termux 里直接驱动这台手机）时需要；用电脑 adb 驱动可以跳过。

所有步骤以**官方文档**为准——本页只做"该看哪一页"的索引，外加我们实战踩过的坑。

> ⚠️ **难度提示：纯 Termux 路线有一定操作难度，建议有一定玩机经验再使用。**
> 它涉及开发者选项、无线调试配对、把 `rish` 放进 Termux 私有目录等步骤，
> 中间还夹着各家厂商的定制限制（见下文表格）。
> 如果只是想用起来，**用电脑 adb 驱动要简单得多**——见仓库 README 的「快速开始」。

## 1. 安装 Termux

- 从 **F-Droid** 或 **GitHub Releases** 安装（Google Play 版已废弃，不要用）。
- 官方安装说明：<https://github.com/termux/termux-app#f-droid>
- 官方 wiki 安装页：<https://wiki.termux.dev/wiki/Installation>

## 2. 安装并启动 Shizuku

Shizuku 提供三种启动方式，**都不需要 root**：

| 方式 | 适用 | 备注 |
| --- | --- | --- |
| root 启动 | 已 root 的设备 | 直接启动 |
| **无线调试** | Android 11 及以上 | **不需要电脑**；每次重启手机后需要重新启动一次 |
| 电脑 adb | Android 10 及以下 | 需要一台电脑 |

官方手册（含每种方式的逐步说明与 FAQ）：

- 简体中文：<https://shizuku.rikka.app/zh-hans/guide/setup/>
- English：<https://shizuku.rikka.app/guide/setup.html>
- 下载：<https://shizuku.rikka.app/download.html>

## 3. 在 Termux 里装运行时

```bash
pkg install nodejs          # 必需：dump.js / px.js 靠 Node.js 运行
pkg install android-tools   # 可选：想用 adb 而不是 rish 时才需要
```

官方包管理文档：<https://wiki.termux.dev/wiki/Package_Management>

## 4. 让 Termux 能调用 Shizuku（`rish`）

按 Shizuku 应用内的 **"Use rish"** 提示，把 `rish` 脚本与 `rish_shizuku.dex` 放进 Termux 的私有目录
（通常就是 `$HOME`），并让 Termux 声明自己是谁：

```bash
export RISH_APPLICATION_ID=com.termux
~/rish -c 'id'          # 期望输出 uid=2000(shell)
```

看到 `uid=2000(shell)` 就说明这条路通了。

## 厂商定制的坑（摘自 Shizuku 官方手册 FAQ）

| 厂商 | 需要做什么 |
| --- | --- |
| **小米 / POCO（MIUI、HyperOS）** | 开发者选项里**额外**打开「**USB 调试（安全设置）**」——它和普通的「USB 调试」是**两个独立开关**，不开会表现为"能连上但很多操作没权限" |
| 小米 / POCO | 无线调试配对失败时，把通知样式切回「Android」 |
| 小米 / POCO | **不要**在小米安全中心里做"扫描"，那会关掉开发者选项 |
| ColorOS（OPPO / 一加） | 关闭开发者选项里的「权限监控」 |
| Flyme（魅族） | 关闭开发者选项里的「Flyme 支付保护」 |
| 通用 | 允许 Shizuku 后台运行；不要关闭「USB 调试」和「开发者选项」；USB 模式设为「仅充电 / 不传输数据」；Android 11+ 打开「停用 adb 授权超时」 |

## 常见问题

- **"连上了但没权限"**：多半就是上表小米那条「USB 调试（安全设置）」没开。
- **重启后不能用了**：用无线调试启动时，Shizuku 在每次重启后都需要重新启动一次（系统限制，不是故障）。
- **`rish` 报 `Request timeout`**：Shizuku 应用进程被系统冻结时无法应答——先把 Shizuku 应用切到前台一次再重试。

## 参考链接（全部为官方）

- Termux 官网 <https://termux.dev/> · 中文 <https://termux.dev/cn/>
- Termux 官方文档 <https://termux.dev/en/docs/>
- Termux 官方 wiki <https://wiki.termux.dev/>
- Termux app 仓库 <https://github.com/termux/termux-app>
- Shizuku 官网 <https://shizuku.rikka.app/>
- Shizuku 用户手册（简体中文）<https://shizuku.rikka.app/zh-hans/guide/setup/>
