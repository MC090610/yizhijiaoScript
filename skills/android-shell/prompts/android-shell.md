---
description: 从 Termux 通过 Shizuku 读取或操控这台安卓手机
argument-hint: "[要执行的操作，例如 截图 / 打开某 App / 看当前前台]"
---

用 **$android-shell** 技能完成任务。用户输入：$ARGUMENTS

先跑 `droid setup`（或 `droid check`）确认 rish / 助手 jar / PATH 都就绪；
遇 5 秒超时先 `droid wake` 唤醒 Shizuku 再重试。
需要读界面时用 `droid ui`；坐标要精确就先 `droid shot` + 像素分析，不要凭截图目测。
提交、发送、删除等不可逆动作一律先经用户确认。
