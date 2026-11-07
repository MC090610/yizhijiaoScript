# yizhijiaoScript（已拆分）

> 这个仓库是早期在手机上摸索出来的原型。现在已拆成两个独立技能仓库，**后续维护都去新仓库**。

---

## 现在去哪

| 原技能 | 新仓库 | 说明 |
|---|---|---|
| `skills/android-quiz` | **[paperlane-tools/android-quiz-skill](https://github.com/paperlane-tools/android-quiz-skill)** | 专用答题：读屏 → 作答 → 逐题校验 → 交卷 |
| `skills/android-shell` | **[MC090610/android-shell-skill](https://github.com/MC090610/android-shell-skill)** | 通用安卓控制：Termux + Shizuku 截图 / 点击 / UI dump / 通知 |

> ⚠️ **答题技能需要前置技能**：先安装 `android-shell`（通用控制），再安装 `android-quiz`。

## 为什么拆

- 两个技能本来就互相独立：quiz 负责题目流程，shell 负责设备层；
- 同时安装会注入两份技能描述，费 token，也容易让弱模型选错技能；
- 分开后可以按需只装一个，各自的 README / 许可证 / 发布也更清晰。

## 旧代码

本仓库保留历史提交，代码不再更新；只作为早期原型的记录。

## 许可证

两个新仓库均为 GPL-3.0-only。本仓库原有内容版权归原作者所有。
