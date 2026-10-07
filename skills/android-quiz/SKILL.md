---
name: android-quiz
description: Drive an Android app's UI to complete a quiz or answer sheet (答题 / 单选 / 补全对话) on a phone or emulator - find the assignment, read the question screen, answer it, verify each selection by pixel, and submit. Works over USB, wireless ADB or an emulator from a computer, or on-device from Termux through Shizuku. Use when the user asks to answer questions inside an Android app. Not for web-only quizzes, desktop apps, or pure file work.
metadata:
  short-description: Answer quizzes inside an Android app
---

# Android quiz runner

Drive an Android app to answer questions. The pattern is always the same:
**find the assignment → read the question → answer → verify → submit**. What
changes per environment is only how you talk to the device.

## What this skill can do

- find the assignment in the app's work list and open it;
- read the question, including when the question itself is an image (open it and
  look at it);
- answer single-choice and multi-blank exercises by tapping the right options;
- verify every selection from the framebuffer instead of guessing;
- submit, after the user confirms;
- report what was answered, what was verified, and the score the app shows.

## Requirements (check, and tell the user what is missing)

- `bash` (Git Bash or WSL on Windows) for `scripts/andev.sh`;
- `node` for the pixel helpers in `scripts/px.js`;
- when driving from a computer: platform-tools `adb` plus the cable/authorisation;
  when driving on-device: Termux plus Shizuku (`rish`);
- the target app installed on the device, and a working login on it.

## How a user invokes it

Two ways, and the second one always works:

1. **Slash command** - `prompts/android-quiz.md` ships with this skill. Copy it to
   the prompt/command directory of whatever agent host is in use, and it becomes
   `/android-quiz [what to do]`:

   | host | directory |
   |---|---|
   | Codex | `$CODEX_HOME/prompts/` (usually `~/.codex/prompts/`) |
   | opencode | `~/.config/opencode/command/` |
   | Claude Code | `~/.claude/commands/` |

   The template takes arguments (`$ARGUMENTS`) and already spells out the two
   mandatory first steps, so the user does not have to remember them.

   Verification note: this build of Codex does contain the custom-command
   machinery (`$ARGUMENTS`, "command template body"), and `prompts/` is the
   long-standing location, but the official page could not be fetched to confirm
   the directory at the time of writing - so after installing, restart the host
   and type `/` to see whether `android-quiz` is listed.
2. **Mention** - typing `$android-quiz` (or picking it in the skill/mention
   picker) always works, because that is the skill mechanism itself. The
   `default_prompt` in `agents/openai.yaml` is what the UI prefills.

When handing this skill to someone else, give them the whole folder **plus** the
`prompts/*.md` file, and tell them to copy the prompt file into their prompts
directory if they want the slash command.

## Step 0 - ask the user first (mandatory)

Before touching anything, ask which target you are working with, and wait:

> 请确认目标设备属于哪种情况：① 通过 USB 连接的实体安卓设备；② 安卓模拟器；③ 设备本身就在跑（Termux 本机，无数据线）？
>
> Which one is it: (1) a physical Android phone over USB, (2) an Android
> emulator, or (3) nothing to connect - this is running on the device itself?

Do not guess from what happens to be attached: a wrong assumption means taps land
on the wrong thing, and the user's own phone is usually in the room.

## Step 1 - prove the environment yourself

After the user answers, detect the facts and report them before acting:

```bash
bash scripts/andev.sh detect      # a report, no side effects
# or, from a bash shell, to get the helpers as functions:
. scripts/andev.sh && andev detect
```

That prints: which transport is usable (`adb` / `rish` / `su`), whether an adb
device is attached and whether it is an **emulator or a physical device**, the
shell identity (`uid=2000` = shell, `uid=0` = root), Android version, screen size,
and whether root is available. Also state explicitly, in your reply:

`andev.sh` needs bash (Git Bash / WSL on Windows are fine). If your shell is
`sh`/`dash` it says so instead of failing obscurely; if bash is not available at
all, use the plain-adb command table below.

- **adb**: installed? device attached? emulator or physical?
- **root**: `su -c id` returning `uid=0` - or "no root".

If `andev detect` shows `transport NONE`, stop and tell the user what to fix
(plug the cable and accept the RSA prompt, `adb connect host:5555`, or open the
Shizuku app once to wake it) instead of improvising.

## Step 2 - use the device memory (calibrate once, reuse after)

The skill remembers each device, so the second run on the same phone skips
detection and calibration entirely:

```bash
andev profile
#   FIRST RUN on this device  -> calibrate, then record what you learned
#   KNOWN device              -> reuse it; do not re-detect, do not re-derive
```

**First time on a device:**

```bash
andev calibrate <optionY>:options <tabY>:qtabs      # detect + learn the row shapes
andev remember <pkg> rows='{"options":1293,"qtabs":973}' \
      selected_rgb='[233,239,252]' unselected_rgb='[242,242,242]' \
      layout_profile=<path to the learned profile>
```

**Every later run:**

```bash
andev profile            # says KNOWN device
andev recall <pkg>       # prints the remembered rows / colours / facts
```

What is remembered: brand, model, API, ROM, resolution, density, transport, the row
shapes, the two selection colours, and anything you store with `andev remember`.
Memory lives in `$ANDROID_QUIZ_HOME` (default `~/.android-quiz`), **one file per
device**, so several phones never clash - the key includes resolution and density,
so changing either yields a new memory instead of a wrong one.

If a remembered value stops matching (app update, theme change), `px_locate_row`
fails or `px_sel` disagrees - that is the signal to re-run `andev calibrate` and
`andev remember` for that app. Do not silently keep tapping a stale profile.

## Transports - same actions, different plumbing

| | `adb` (USB / wireless / emulator) | `rish` (on-device Shizuku) | `su` (root) |
|---|---|---|---|
| reach | from a computer with platform-tools | inside Termux | inside Termux |
| identity | shell (uid 2000) | shell (uid 2000) | root (uid 0) |
| needs | cable+授权, or `adb connect` | Shizuku started | rooted device |

`andev.sh` hides the difference behind `dev_tap / dev_swipe / dev_key /
dev_text / dev_fg / dev_shot_raw / dev_batch / dev_seq`, so an action string
written once works on all three. Keep that separation: the actions are data, the
transport is interchangeable.

## If bash or node is not available (plain adb only)

Any agent on any OS can still do the whole job with just platform-tools:

| operation | command |
|---|---|
| list targets | `adb devices -l` |
| one-off shell | `adb shell '<cmd>'` |
| tap / press | `adb shell input tap X Y` / `adb shell input swipe X Y X Y 120` |
| key / text | `adb shell input keyevent 4` / `adb shell input text 'abc'` |
| focused app | `adb shell dumpsys window \| grep -m1 mCurrentFocus` |
| launch app | `adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1` |
| raw frame | `adb exec-out screencap > frame.raw` |
| png frame | `adb exec-out screencap -p > shot.png` |

Binary-safety notes, they matter:

- always use **`adb exec-out`**, never `adb shell ... > file` - `adb shell`
  mangles line endings and corrupts binary output;
- on **PowerShell** `>` is not byte-safe either: use
  `adb exec-out screencap -p | Set-Content -Encoding Byte shot.png`, or run the
  command from `cmd.exe` / Git Bash / WSL;
- `grep` may not exist on Windows: `adb shell dumpsys window | findstr mCurrentFocus`.

Pixel analysis needs node (`scripts/px.js`). Without node, lean on the text path
instead: `adb shell uiautomator dump` + your own parsing of `text="..."` and
`bounds="..."` works on hybrid WebViews too - just anchor on the last `【第N题】`
so the previous page's leftovers do not fool you.

## The loop

1. **Get to the assignment.** Launch the app, go to the work list, open the item.
   The list can re-sort after a submission - always confirm the screen you landed
   on matches the assignment you meant (read the title, do not trust the row
   coordinate you used last time).
2. **Read the question.** If the question is an image, open it (tap the paper
   thumbnail) and screenshot it; that single screenshot is the one place where
   reading with vision is genuinely needed. If you have OCR available, use it.
3. **Answer in one guarded batch.** All taps with their waits in a single
   `dev_batch`/`dev_seq`, so the whole answer pass costs one round trip.
4. **Verify by pixel**, not by another screenshot for the eyes: `px_sel` on each
   option, `px_find` to locate a control whose coordinates you are unsure of.
5. **Submit only when the user asked for it.** "Answer these" is not the same as
   "submit the exam". Confirm before the final 交卷/提交, then handle the
   confirmation dialog (`px_find red` finds its buttons).
6. **Report** what was selected per question, what you verified, and the score if
   the app shows one.

## Reading the screen: text first, pixels to confirm

`uiautomator dump` **does work** on this app's hybrid WebView - one call returns
the stem, every option label and the real bounds of every button. That is far
cheaper than looking at screenshots, so try it first:

```bash
XML=$(dev_dump)                  # one dump, copied back locally
dump_quiz "$XML"                 # question number, stem, options, buttons + bounds
dump_nodes "$XML"                # every text node, ordered by y
dump_find "$XML" 下一题           # bounds of one label
DIR=$(dev_collect 49 下一题 1.1)  # walk the whole set in ONE round trip
```

Rules that make dumps usable (each learned the hard way):

- **Anchor on the LAST 【第N题】.** The tree still holds the previous page, so an
  earlier match can belong to the work list.
- **No anchor means the app is not in the foreground** (a dump can silently
  return the desktop). Retry a couple of times, or `dev_app` first.
- **Prefer the dump's bounds to any remembered coordinate.** Both the option row
  and the 下一题 button move between questions; 下一题 was measured at
  y=1531/1582/1588/1633/1645 in one 49-question set.
- Use pixels (`px_sel`) only to **confirm** that a tap landed.
- If a question is an image with no text nodes, fall back to `dev_capture` +
  `px_sweep` / `px_selected`.

## First run on a new device: calibrate, never copy

Nothing in this skill is tied to one phone or one ROM. The transports are generic
(`adb` from any OS, `rish` on-device), the pixel threshold is derived from the
frame width, and every coordinate is either read from a dump or learned from the
device. **The numbers quoted in the playbook are one device's example - use them
to sanity-check a result, not to tap.**

Calibration takes about a minute and needs no hard-coding:

```bash
andev detect                                   # resolution, API, root, transport
PKG=<the quiz app>
dev_app "$PKG"
XML=$(dev_dump); dump_quiz "$XML"              # stems + option labels + tapY + buttons
#   -> if it reports "no 【第N题】 anchor", the app is not in the foreground, or the
#      app exposes no text at all: then use the pixel path below instead

dev_shot_raw; SIZE=$(px_size)
PROFILE=~/.android-quiz/$PKG-$SIZE.json        # one profile per package+screen
dev_learn_layout "$PROFILE" <optionY>:options <tabY>:qtabs   # y values from dump_quiz
```

Everything after that is derived at run time: tap targets from the current dump or
the learned profile, row shifts via `px_locate_row` in a y-band, and the selection
check via `px_sel` against the colours measured on **this** device.

If all you have is a coordinate list from another device, scale it as a rough
starting guess (`x * W_new/W_old`, `y * H_new/H_old`) and then confirm with
`px_find` before tapping - density differs too, so never reuse a point blind.

What is genuinely device-dependent (re-measure these): the selected/unselected
colours, the option-row y, the question-tab y, and the dialog button positions.
Everything else is structural and transfers.

### The three dialogs you will meet

| dialog | text | buttons |
|---|---|---|
| leaving the quiz | `你有正在作答的试卷 / 确定退出吗？` | 再想想 (≈761,1577) · 直接退出 (≈982,1577) |
| submitting | `确认提交？` | 确定 (≈816,1493) · 取消 (≈1007,1493) |
| assignment expired | `任务已经截止` | only 知道了 (≈1002,1493) |

Read the dialog text before tapping: the same coordinates can be a different
dialog, and `px_find red` merges both button labels into a single bbox - so read
the dump rather than guessing which button is which.

### Work-list states

- The list **re-sorts after a submission**; a row's y must be re-located every time.
- A returned assignment shows `待重做` / `上次成绩` / `打回理由`.
- **`重做` exists in two different states with different coordinates** (card
  ≈595,2164, fullscreen ≈595,2427) - locate it, never memorize it.
- Expired assignments cannot be submitted (`任务已经截止`); check the deadline
  before doing the work at all.

## Cost model - round trips are the bottleneck

Measured on a real 2h21m quiz session: **190 tool round trips** (125 shell calls +
65 image views), median **14 s** per step, image views alone ~16 minutes. The
device work is cheap by comparison: a tap ~0.4 s, a raw frame 0.5-1.8 s, a row
scan ~0.05 s.

So optimise in this order:

1. **Fewer round trips.** One call that does N things beats N calls. A whole
   assignment should take about four: capture, answer, verify, submit.
2. **Fewer vision steps.** One screenshot to read the paper; everything else is
   pixels or text. Never look at a screenshot to verify something a pixel check
   can answer.
3. **Reuse instead of re-detect.** Learn the stable rows once, locate the moving
   ones by shape; never re-scan a whole frame for a position you already know.
4. Only then tune per-action latency (shorter waits, a resident transport).

## When template matching (OpenCV) is actually worth it

Not for this app's controls. Option boxes and question numbers are regular rows,
so a single-row scan yields count, pitch and centres in ~50 ms - and it survives
the selected/unselected colour change that defeats naive colour matching (those
two fills differ by only ~22).

Reach for classic template matching / OpenCV only when:

- elements are **not** on a regular row (scattered icons, floating buttons);
- you must match a **picture** (logo, sprite, scanned glyph) rather than a shape;
- the same element appears at arbitrary rotation or scale;
- you need **OCR preprocessing** (crop, deskew, binarise, upscale) to read a
  scanned paper - that is where OpenCV pays off most in this workflow.

## Reuse the layout - do not re-detect it every pass

Measured on a real 2h21m run: **190 tool round trips** (125 shell + 65 image
views), median **14 s** per step. A naive loop re-reads the screen for nearly
every tap. That is the waste to remove, and the fix is two-part.

**(a) Rows whose position is stable: learn once, then only re-check.**

Learn the fixed rows **once per app + screen size**, then only re-check them:

```bash
PROFILE=~/.android-quiz/cn.campsg.spoc4-1220x2712.json

# once: one frame, learn the two option rows and the question-number row
dev_learn_layout "$PROFILE" 1293:options 1413:options2 973:qtabs

# every later pass: one single-row scan each (~50 ms), no full-image search
dev_check_layout "$PROFILE"          # exits non-zero if the structure changed
dev_tap_el "$PROFILE" options D      # taps the remembered centre
dev_tap_el "$PROFILE" qtabs 3
```

Why this is verifiable at all: the selected and unselected fills differ by only
~22 (242,242,242 vs 233,239,252), so a colour check cannot tell "this option is
selected" from "the box moved". What *does* survive selection, theme and content
changes is the **row structure** - the count, order and pitch of the non-white
runs along a line through the boxes. `check-rows` compares that structure, allows
up to `tol` px of drift (default 6), writes the corrected centres back into the
profile, and reports `CHANGED` when the app really did move something.

Re-learn only when `dev_check_layout` says `CHANGED` (new device, app update,
different theme or font scale). Keep one profile per package+resolution so
switching devices does not invalidate the other one.

**(b) Rows that move: find the shape, not the coordinates.**

The option row **shifts vertically with the length of the question stem** - in the
measured run the same row appeared at y=1293, 1279, 1404, 1445, 1577 and 1651 for
different questions. A remembered y is therefore useless, and re-reading the
screen to find it again is what made that run slow.

Instead, learn the row's **shape** once (how many runs, their pitch and span) and
then locate it inside a y-band on any frame:

```bash
dev_learn_layout "$PROFILE" 1293:options          # once: shape of the option row
dev_locate_row "$PROFILE" options 1150,1700       # live screen: finds y automatically
px_sweep "$PROFILE" options 1150,1700 ~/.andev-shots   # or all captured frames
```

Verified behaviour: with a frame shifted down by 40 px, `locate-row` returned
`y=1840` instead of the learned `1800`, with the same run count and pitch.

**(c) Capture a whole question set in one round trip.** `dev_capture <tabY>
<tabX...>` taps each question tab and writes one raw frame per question in a
single call; then `px_sweep` locates every question's row locally. That turns
"look, tap, look, tap, ..." into **one capture + one answering batch + one
verification batch** for the whole assignment.

The intended shape of an assignment is therefore ~4 round trips total: capture,
answer, verify, submit.

## Rules that prevent the classic failures

- **Never turn a viewed screenshot into tap coordinates.** The image shown to you
  is scaled by an unknown factor; a real measurement was off by 137 px. Locate
  controls with `px_find` / `px_blocks` instead.
- **Guard the foreground** before every batch (the helpers do). If the user picks
  up the phone mid-run, the batch refuses instead of tapping their app.
- **`uiautomator` IS usable on hybrid (uni-app / WebView) screens** - it returns
  the stem, the option labels and every button bound. But the tree also holds the
  *previous* page, so anchor on the last `【第N题】` (see "Reading the screen"), and
  treat a missing anchor as "the app is not in front", not as "dumps do not work".
  An earlier version of this skill wrote it off after a mis-anchored dump; a
  49-question run then showed it is the fastest way to read the screen.
- **Dialogs** have no package in `mCurrentFocus`, so the guard blocks; use the
  unguarded path only after you have seen the dialog, and locate its buttons by
  colour.
- **Chunk long batches**: 10-15 questions per guarded batch, re-checking the
  foreground at the start of each chunk. One 49-question batch that began while
  another app was focused silently tapped through Termux and corrupted seven
  answers.
- **A failed guard means stop, not "carry on".** The helpers return non-zero; if
  you ignore that, taps land in whatever app is actually in front.
- **Never build an action from empty coordinates.** A failed parse once produced
  `input swipe 600 0 600 0 120` - a silent tap at the very top of the screen.
  Assert that the parse yielded numbers before tapping.
- **A failed verification must be retried immediately** (re-tap, re-check). One
  run submitted with an unverified answer and scored 50.
- **Never submit while any answer is unverified.**
- **Clean up on the device.** Every helper writes its device-side scratch under
  `/sdcard/.andev` and deletes it once the result has been fetched locally;
  `dev_clean` removes the whole scratch directory. Raw frames are 13 MB each -
  an earlier run left five of them (64 MB) sitting in the phone's storage root,
  which is exactly the kind of litter to avoid.
- **Clean up** the temp frames you create.

## Safety

- Never delete, move or overwrite the user's files (albums, messages, documents),
  and never "tidy up" on your own initiative.
- Answering on the user's behalf is their call, but **submitting** is
  irreversible: get explicit go-ahead first, or leave it for them to press.
- Only the answers requested are typed; nothing is sent anywhere else.

## Worked example

[references/quiz-playbook.md](references/quiz-playbook.md) has both measured
flows with their real numbers:

- **text-first** - a 49-question set walked in ~7 round trips / ~10 min (96 分);
- **pixel path** - a 5-question set in ~6 round trips / ~45 s.

The raw evidence behind those numbers (per-question y samples, the three dialogs,
the answers a bad batch corrupted, the submission that skipped verification) is
in [references/field-notes-2026-09-29.md](references/field-notes-2026-09-29.md).
