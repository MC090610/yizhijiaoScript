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

`android-shell` 是底座：`android-quiz` 在 Termux 本机跑的时候会用到它提供的 `rish` 与通知能力；
纯 adb 场景下只装 `android-quiz` 也能用。

## 快速开始

**前置条件**

| 依赖 | 版本/说明 |
| --- | --- |
| Node.js | 运行 `dump.js` / `px.js`（解析与像素分析） |
| Bash | 运行 `andev.sh`（Windows 用 Git Bash 或 WSL） |
| adb（platform-tools）**或** Termux + Shizuku | 二选一，`andev detect` 会自动选择 |

**1. 安装技能**

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
cp -R skills/android-quiz  "${CODEX_HOME:-$HOME/.codex}/skills/"
cp -R skills/android-shell "${CODEX_HOME:-$HOME/.codex}/skills/"

# 可选：让斜杠命令 /android-quiz 可用（重启 Codex 后生效）
mkdir -p "${CODEX_HOME:-$HOME/.codex}/prompts"
cp skills/android-quiz/prompts/android-quiz.md "${CODEX_HOME:-$HOME/.codex}/prompts/"
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
