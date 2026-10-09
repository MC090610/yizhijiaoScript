<h1 align="center">yizhijiaoScript</h1>

<p align="center">
  <b>让 AI 在安卓答题 App 里替你读题、作答、校验、交卷。</b><br>
  两个面向 Codex / OpenClaw 等 Agent 的技能（Skill），默认适配「易智教」这类 uni-app 答题页，
  实测在一份 49 题的测验上拿到 <b>48/49</b>。
</p>

<p align="center">
  <a href="https://www.android.com"><img alt="Platform: Android" src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white"></a>
  <a href="https://termux.dev"><img alt="Runtime: Termux" src="https://img.shields.io/badge/Runtime-Termux-000000?logo=gnubash&logoColor=white"></a>
  <a href="https://shizuku.rikka.app"><img alt="Privilege: Shizuku" src="https://img.shields.io/badge/Privilege-Shizuku-5B6CC6"></a>
  <img alt="Agent Skill: Codex" src="https://img.shields.io/badge/Agent%20Skill-Codex-412991">
  <a href="https://github.com/MC090610/yizhijiaoScript/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/MC090610/yizhijiaoScript?color=ff5a1f"></a>
</p>

<p align="center">
  <a href="#快速开始">快速开始</a> ·
  <a href="#技能清单">技能清单</a> ·
  <a href="#使用前置termux--shizuku">使用前置</a> ·
  <a href="#设计要点">设计要点</a> ·
  <a href="#安全边界">安全边界</a> ·
  <a href="#已知限制">已知限制</a>
</p>

## 这是什么

一套在安卓手机上做「答题类 App 自动化」的技能。核心思路只有两条：

- **能读文本就不看图**：一次 `uiautomator dump` 就能拿到题干、选项和每个按钮的真实坐标，
  比逐张截图判断便宜一个数量级。
- **能一次调用就不来回点**：把「守卫前台 → 批量点击 → 截图」合成一次调用，
  一份 49 题的测验从上百次工具往返压到 **约 7 次**。

适合谁：用 Agent（Codex / OpenClaw）驱动安卓设备做题、批量处理在线测验的人。
两种接入都支持——**电脑用 adb**，或**手机本机用 Termux + Shizuku**（无需 root）。

## 技能清单

| 技能 | 用途 | 关键内容 |
| --- | --- | --- |
| [`skills/android-quiz`](skills/android-quiz/) | 在安卓 App 里答题：找作业 → 读题 → 作答 → 逐题校验 → 交卷 | 文本优先读屏、守卫批量、像素校验、设备记忆、实战记录 |
| [`skills/android-shell`](skills/android-shell/) | 从 Termux 通过 Shizuku 读写这台手机 | 截图、点击、UI dump、通知（含手环推送）、媒体读取 |

**两个技能互相独立，按需只装一个**：

- `android-quiz` 自带传输层（`adb` / `rish` / `su`）与像素工具，**不依赖** `android-shell`；
- `android-shell` 提供通用的手机控制（截图、点击、通知、媒体），答题时用不到就可以不装。

同时装两个会让每次会话都注入两份技能描述——**更费 API，弱一些的模型也更容易挑错技能**，
所以推荐"用到哪个装哪个"。

## 使用前置（Termux + Shizuku）

走**手机本机**路线时，需要先准备 Termux + Shizuku（**无需 root**）。
安装步骤、官方文档入口，以及小米/POCO 那个「USB 调试（安全设置）」的坑，都在这份单独文档里：

➡️ **[Termux + Shizuku 使用前置（含各厂商 FAQ）](docs/termux-setup.md)**

> ⚠️ **纯 Termux 路线有一定操作难度**：要做开发者选项、无线调试配对、把 `rish` 放进 Termux 私有目录，
> 还要应付各家厂商的定制限制。**建议有一定玩机经验再使用**；只想省事的话，用电脑 adb 驱动即可，
> 配置简单得多。

## 快速开始

### 一句话安装（推荐）

把**对应那一句**发给你的 Agent 就行（Codex / OpenClaw 都适用）。两句话是分开的，
你只需要复制用到的那句。

**① 只装答题技能（`android-quiz`）** —— 找作业 → 读题 → 作答 → 逐题校验 → 交卷；
电脑 adb 或 Termux + Shizuku 都能跑。

> 从 https://github.com/MC090610/yizhijiaoScript 安装 `skills/android-quiz` 到我的个人技能目录
> （Codex 是 `$CODEX_HOME/skills`，OpenClaw 用 `openclaw skills install`），
> 再把 `skills/android-quiz/prompts/android-quiz.md` 放进 prompts / command 目录；
> 最后按 `android-quiz/SKILL.md` 的 Step 0 和 Step 1 自检环境（缺 Node.js、bash、adb
> 或 Termux+Shizuku 时先告诉我），并汇报：传输方式、是实体机还是模拟器、有没有 root。

**② 只装 Termux 控制技能（`android-shell`）** —— 截图、点击、UI dump、通知（含手环推送）、
媒体读取；Termux + Shizuku 本机使用。

> 从 https://github.com/MC090610/yizhijiaoScript 安装 `skills/android-shell` 到我的个人技能目录
> （Codex 是 `$CODEX_HOME/skills`，OpenClaw 用 `openclaw skills install`），
> 再把 `skills/android-shell/prompts/android-shell.md` 放进 prompts / command 目录；
> 装好后跑 `skills/android-shell/scripts/droid.sh setup` 自检（rish、通知助手、PATH），
> 并告诉我结果；想要短命令 `droid` 就把它软链到 `~/bin/`。

**两个都要**：把上面两句一起发过去即可。
每个技能自检完都会告诉你「能不能用、缺什么」，缺东西时应当直接说明该怎么修，而不是硬猜。

### 手动安装（等价做法）

**前置条件**

| 依赖 | 版本/说明 |
| --- | --- |
| Node.js | 运行 `dump.js` / `px.js`（解析与像素分析） |
| Bash | 运行 `andev.sh`（Windows 用 Git Bash 或 WSL） |
| adb（platform-tools）**或** Termux + Shizuku | 二选一，`andev detect` 会自动选择；走 Termux 路线请先完成上一节 |

**1. 安装技能**

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"

# 只装答题技能（自带 adb / rish 传输层，不依赖另一个技能）
cp -R skills/android-quiz "${CODEX_HOME:-$HOME/.codex}/skills/"

# 需要 Termux 本机控制（截图 / 通知 / 媒体）时再装这个；用不到可以不装
cp -R skills/android-shell "${CODEX_HOME:-$HOME/.codex}/skills/"

# 可选：让斜杠命令 /android-quiz 可用（重启 Codex 后生效）
mkdir -p "${CODEX_HOME:-$HOME/.codex}/prompts"
cp skills/android-quiz/prompts/android-quiz.md   "${CODEX_HOME:-$HOME/.codex}/prompts/"  # /android-quiz
cp skills/android-shell/prompts/android-shell.md "${CODEX_HOME:-$HOME/.codex}/prompts/"  # /android-shell
```

**2. 先确认环境**

```bash
. skills/android-quiz/scripts/andev.sh
andev detect
```

输出会告诉你：传输方式（`adb` / `rish` / `su`）、设备是**实体机还是模拟器**、**有没有 root**、
Android 版本与屏幕尺寸。没有可用传输时它会直接说明该怎么修，而不是硬猜。

**3. 第一次在某台设备上（标定一次，之后复用）**

```bash
andev profile                              # FIRST RUN / KNOWN device
andev calibrate 1293:options 973:qtabs     # y 用 dump_quiz 得到的真实值
andev remember <package> rows='{"options":1293}' selected_rgb='[233,239,252]'
```

设备指纹包含分辨率与密度，**一台设备一份记忆**；换手机、改分辨率都会生成新档案，不会拿错坐标。

**4. 干活**

```bash
XML=$(dev_dump); dump_quiz "$XML"      # 题干 + 选项文字 + 每个按钮的真实坐标
DIR=$(dev_collect 49 下一题 1.1)       # 一次调用走完整套题
```

完整的两条路线（文本优先 / 像素路线）、实测耗时与失败模式表见
[`skills/android-quiz/SKILL.md`](skills/android-quiz/SKILL.md) 与
[`skills/android-quiz/references/quiz-playbook.md`](skills/android-quiz/references/quiz-playbook.md)。

## 设计要点

- **不挑设备**：分辨率不写死，像素阈值按帧宽推导；坐标一律来自 dump 或现场学习；
  同一台手机第二次直接复用记忆。
- **守卫**：任何批量动作前先确认目标 App 在前台，否则**拒绝执行**——避免点到别的应用上。
- **分块与自愈**：长批量按 10–15 题切块，每块重校验前台；守卫失败即中止。
- **校验优先于交卷**：逐题像素确认，**校验不过必须重做**，绝不带病交卷。
- **失败要吵**：坐标解析为空则断言失败、不构造动作（实战中出现过静默点到屏幕顶端的案例）。

## 验证

```bash
bash -n skills/android-quiz/scripts/andev.sh        # 脚本语法
node --check skills/android-quiz/scripts/dump.js    # 解析器语法
python3 skills/android-quiz/scripts/px.js 2>/dev/null || true   # 像素工具由 node 运行
```

真机验证顺序：`andev detect` → `dev_dump` + `dump_quiz`（应看到题干与选项）→
`dev_capture` 后 `px_selected`（应报出每题选中项）。

## 安全边界

- **不删除、不移动**用户的相册、短信、文件；不「自作主张清理」。
- **交卷 / 提交属于不可逆动作**，必须由用户明确确认后才执行。
- 只操作被点名的目标 App，批量动作前先校验前台。
- 实战记录里的练习内容（题干、答案、课程名、分数）在公开版中已隐去；
  本机技能副本仍保留原文。

## 已知限制

- 题干解析是启发式（取字母标签之上最长的文本），**换 App 需要自检**；
  选项识别是结构性的（单字母标签 + 左边距 + 同 y 右侧文本），跨 App 更稳。
- 虚拟屏（不占用手机主屏地跑任务）在 Android 16 上不可用：系统裁掉了创建命令，
  开发者选项造出的叠加屏 `canHostTasks=false`，无法承载应用。
- 文档中的具体坐标来自一台 1220×2712 设备，换设备请用 `dump_quiz` 重新推导。

## 许可

本仓库暂未添加 `LICENSE` 文件，因此首页也没有 license 徽章。
若要开源分发，建议先补一份明确许可（例如 MIT）。
