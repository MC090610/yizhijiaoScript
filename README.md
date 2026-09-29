# yizhijiaoScript

在安卓手机上做「答题类 App」自动化的两个 Codex 技能（skill）。默认面向
**易智教**（`cn.campsg.spoc4`）这类 uni-app/WebView 答题页，也能改用别的答题 App。

核心思路：**能读文本就不看图，能一次调用就不来回点**。

## 里面有什么

```
skills/
├── android-quiz/     在安卓 App 里答题：找作业 → 读题 → 作答 → 校验 → 交卷
│   ├── SKILL.md
│   ├── agents/openai.yaml          界面元数据（含 default_prompt）
│   ├── prompts/android-quiz.md     斜杠命令模板（$ARGUMENTS）
│   ├── references/                 实战套路 + 一份真机实战记录
│   └── scripts/
│       ├── andev.sh                传输层（adb / rish / su）+ 守卫批量 + 设备记忆
│       ├── dump.js                 解析 uiautomator dump（题干/选项/按钮坐标）
│       └── px.js                   像素工具（定位控件、判断选中）
└── android-shell/    从 Termux 通过 Shizuku 读写这台手机（截图/点击/通知/媒体）
```

## 依赖

| 依赖 | 用途 | 备注 |
|---|---|---|
| `bash` | 跑 `andev.sh` | Windows 用 Git Bash / WSL |
| `node` | 跑 `dump.js` / `px.js` | 解析与像素分析 |
| `adb`（platform-tools） | 从电脑驱动手机 | 或者用下一条 |
| Termux + Shizuku | 在手机本机驱动自己 | `rish`，uid=2000，无需 root |

两种接入都行，`andev detect` 会自动选择。

## 安装

```bash
# 1) 技能
mkdir -p ~/.codex/skills
cp -r skills/android-quiz  ~/.codex/skills/
cp -r skills/android-shell ~/.codex/skills/

# 2) 斜杠命令（可选，让 /android-quiz 可用）
mkdir -p ~/.codex/prompts
cp skills/android-quiz/prompts/android-quiz.md ~/.codex/prompts/
#   opencode:  ~/.config/opencode/command/
#   Claude Code: ~/.claude/commands/
```

重启 Codex 后，输入 `/` 应能看到 `android-quiz`；没出现就直接用 `$android-quiz`。

## 快速开始

```bash
. skills/android-quiz/scripts/andev.sh

andev detect        # 传输方式 / 实体机还是模拟器 / 有没有 root —— 先看这个
andev profile       # 第一次：FIRST RUN；以后：KNOWN device（记住过就直接复用）

# 第一次在某台设备上
andev calibrate 1293:options 973:qtabs
andev remember cn.campsg.spoc4 rows='{"options":1293,"qtabs":973}' \
      selected_rgb='[233,239,252]' unselected_rgb='[242,242,242]'

# 之后每次
XML=$(dev_dump); dump_quiz "$XML"     # 题干 + 选项文字 + 每个按钮的真实坐标
DIR=$(dev_collect 49 下一题 1.1)      # 一次调用走完整套题（每题的 dump）
```

细节（两条完整路线、实测耗时、失败模式表）见
[`skills/android-quiz/SKILL.md`](skills/android-quiz/SKILL.md) 与
[`references/quiz-playbook.md`](skills/android-quiz/references/quiz-playbook.md)。

## 设计要点

- **不挑设备**：分辨率/密度不写死，`min_run` 按帧宽推导；坐标一律来自
  `dump` 或现场学习；设备指纹 + 记忆让同一台手机第二次直接复用。
- **文本优先**：`uiautomator dump` 一次给出题干、选项与按钮坐标，比逐张看截图便宜得多。
- **守卫**：任何批量动作前先确认目标 App 在前台，否则拒绝执行（避免点到别的应用上）。
- **可复用的两条路线**：文本优先（大题量）与像素路线（图片题/小题量）。

## 安全

- 不删除、不移动用户的相册/短信/文件；不"自作主张清理"。
- **交卷（提交）属于不可逆动作**：必须由用户明确确认后才执行。
- 校验没通过的题必须重做，**不带病交卷**。

## 已知限制

- 题干解析用的是启发式（字母标签之上最长文本），换 App 需要自检。
- 虚拟屏（不占用手机主屏）在 Android 16 上暂不可用。
- 实战记录里的具体坐标是某台 1220×2712 设备的实测值，换设备请用 `dump_quiz`
  重新推导。
