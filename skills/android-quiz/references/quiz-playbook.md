# Worked example: a 7-option "complete the dialogue" exercise

Measured on 2026-09-28 against 易智教 (`cn.campsg.spoc4`, a uni-app hybrid app,
1220x2712, Android 16). **Treat the geometry below as an example profile, not a
constant.** On another phone (or after an app update) derive it instead of copying
it - `dump_quiz` prints the option labels and their real `tapY`, and `px_blocks` /
`px_find` locate anything the dump does not cover. See "First run on a new device"
in SKILL.md.

## Screen shape

The app's quiz page shows: a paper thumbnail on top (the scanned question), a row
of question tabs, the option buttons for the current question, and two buttons at
the bottom (`上一题` / `下一题`, and on the last question the right one becomes
`交卷`). The top bar also has a `交卷` text button.

Example profile (this device):

| element | coordinates |
|---|---|
| option row 1 `A B C D E F G` | x = 144, 273, 402, 531, 660, 789, 918 - **y moves** (1293/1279/1404/1445/1577/1651 seen); locate it, do not trust y |
| option row 2 `H I J` | y=1413, x = 144, 273, 402 |
| `下一题` (questions 1-4) | (889, 1615) - **on question 5 this is `交卷`** |
| `上一题` | (331, 1615) |
| question tabs 1-5 | y=973, x = 106, 251, 396, 541, 686 |
| paper thumbnail (opens the viewer) | (596, 508) |
| `交卷` in the top bar | (1145, 193) - found with `px_find bluish 850,100,1210,300` |
| submit dialog | `确定` (816, 1493), `取消` (1007, 1493) - found with `px_find red 500,1350,1250,1550` |
| selected option colour | (233, 239, 252); unselected (242, 242, 242) |

Note `交卷` sat at x=1145 while an eyeball estimate from a screenshot said 1008 -
that 137 px gap is why controls are located by colour, not by looking.

## Which path

Try **text-first** first: `uiautomator dump` works on this app's hybrid WebView and
returns the stem, the option labels and every button's real bounds. Fall back to
the **pixel path** only when the dump has no content (image-only questions) or to
confirm that a tap landed.

## Text-first path (measured on a 49-question set, scored 96)

```bash
. scripts/andev.sh
andev detect
PKG=cn.campsg.spoc4
dev_app "$PKG"                        # work list -> open the assignment

# 1) walk the WHOLE set in one round trip: dump -> tap 下一题 -> dump ...
DIR=$(dev_collect 49 下一题 1.1)       # 49 XML files, ~5 min of device time
for f in "$DIR"/*.xml; do dump_quiz "$f"; done   # local parse, < 1 s

# 2) answer from the parsed text, in chunks of 10-15 questions, each chunk
#    guarded (dev_seq) - and stop if a guard fails, do not continue
dev_seq "$PKG" '<per question: tap its option centre, then that question'"'"'s
                下一题 centre - both taken from THAT question'"'"'s dump>'

# 3) verify each answer against a fresh dump (or px_sel); RETRY every mismatch
# 4) submit only when every answer is verified
dev_seq "$PKG" 'input swipe 1145 193 1145 193 120; sleep 2.5'
dev_dump && dump_find ~/.andev-dump.xml 确认提交      # read the dialog, then tap
```

That run took **≈7 round trips** (open, collect, answer, verify, fix, submit,
confirm) instead of the 100+ a per-question screenshot loop needs. Hard rules it
taught, worth repeating:

- anchor on the **LAST** `【第N题】`; no anchor means the app is not in front -
  retry, do not guess;
- both the option row **and** `下一题` move between questions; take their bounds
  from the current dump (`下一题` was seen at y=1531/1582/1588/1633/1645);
- chunk batches, abort on a failed guard (one batch ran while another app was
  focused and corrupted seven answers);
- never build an action from empty coordinates (a bad parse once produced
  `input swipe 600 0 600 0 120`);
- a failed verification must be retried before submitting - one run scored 50 by
  submitting an unverified answer.

## Pixel path (small sets, or image-only questions)

```bash
. scripts/andev.sh
andev detect                     # transport + emulator/physical + root
PKG=cn.campsg.spoc4
PROFILE=~/.android-quiz/$PKG-1220x2712.json

# 0) ONCE per app+screen: learn the SHAPE of the rows (count + pitch), not a y
dev_app "$PKG"
dev_learn_layout "$PROFILE" 1293:options 1413:options2 973:qtabs

# 1) open the assignment and the paper - this is the ONE vision step
dev_seq "$PKG" 'input swipe 1081 576 1081 576 120; sleep 3.5;
                input swipe 596 508 596 508 120; sleep 2.5'
dev_shot_png ~/paper.png         # read it, and confirm the title matches
dev_seq "$PKG" 'input keyevent 4; sleep 2'    # close the viewer

# 2) ONE call captures one frame per question
SHOTS=$(dev_capture 973 106 251 396 541 686)

# 3) locate each question's option row LOCALLY - the row moves with the stem
px_sweep "$PROFILE" options 1150,1700 "$SHOTS"
#   q1.raw  options: y=1404 runs=7 centres=[...]
#   q2.raw  options: y=1293 runs=7 centres=[...]
#   -> use THESE per-question y values below, never a remembered 1293

# 4) answer in ONE guarded batch: per question, its option at ITS y, then next
dev_seq "$PKG" 'input swipe <xC> <y1> <xC> <y1> 120; sleep 1.1;
                input swipe 889 1615 889 1615 120; sleep 1.1;
                ... one pair per question ...'

# 5) verify the whole set in ONE capture + ONE local call
SHOTS2=$(dev_capture 973 106 251 396 541 686)
px_selected "$PROFILE" options "$SHOTS2" 1150,1700
#   q1.raw: y=1404 runs=7 selected=D
#   q2.raw: y=1293 runs=7 selected=A   ... (exits non-zero if any frame is off)

# 6) submit - ONLY after the user confirmed
dev_seq "$PKG" 'input swipe 1145 193 1145 193 120; sleep 2.5'
px_find red 500,1350,1250,1550        # locate 确定, or use (816,1493)
dev_sh 'input swipe 816 1493 816 1493 120'
dev_shot_png ~/after.png              # confirm the score / list shows 已完成
```

## Answers used (recorded so a repeat of the same paper is instant)

The value of this section is the *mechanism*, not the answers: keep a local note
of `paper thumbnail -> answers` so a paper that reappears (the same exercise was
reused across two assignments in practice) can be answered instantly. The concrete
answers are deliberately **not** shipped in this repository - store them in your
own copy or in the device memory (`andev remember`).

## Timer budget

Text-first, 49 questions (measured):

| step | round trips | cost |
|---|---|---|
| open the assignment | 1 | ≈ 10 s |
| collect the whole set (dump + 下一题 per question) | 1 | ≈ 5 min |
| parse locally | 0 | < 1 s |
| answer (chunks) | 1 | ≈ 80 s |
| verify every question | 1 | ≈ 2 min |
| fix the mismatches | 1 | ≈ 40 s |
| submit + dialog + confirm score | 1 | ≈ 15 s |
| **total** | **≈ 7** | **≈ 10 min** |

Pixel path, 5 questions:

| step | round trips | cost |
|---|---|---|
| open app + assignment + paper | 2 | ≈ 10 s |
| read the paper with vision | - | 5-15 s (the only vision step) |
| capture every question | 1 | ≈ 8 s |
| locate the rows (local) | 0 | < 0.3 s |
| answer every question | 1 | ≈ 10 s |
| verify (capture + local check) | 1 | ≈ 8 s |
| submit + dialog | 1-2 | ≈ 5 s |
| **total** | **≈ 6** | **≈ 45 s** |

For contrast, the first real session spent **190 round trips / 2 h 21 m** on the
same kind of assignment, because every tap was preceded by its own look.

Optimisation levers, in order of value: drop the inter-tap wait from 1.1 s toward
0.6 s (validate first); keep a resident transport so a tap costs ~10 ms instead of
~400 ms; cache paper -> answers; use OCR so the paper does not need vision.

## Failure modes met in practice

| symptom | cause | fix |
|---|---|---|
| tap seems to do nothing | the app was not focused - the tap hit another app | the foreground guard in `dev_batch` |
| tapped the wrong place | coordinates estimated from a scaled screenshot | `px_find` / `px_blocks` |
| entered the wrong assignment | the work list re-sorts after a submission | confirm the title after opening |
| option tap misses after a new question | **the option row shifts with the length of the stem** (seen at y=1293/1279/1404/1445/1577/1651) | `px_sweep` / `px_locate_row` inside a y-band; never trust a remembered y |
| `uiautomator` returns the previous page | hybrid WebView | do not use it here; pixels instead |
| dialog cannot be tapped | `mCurrentFocus` is a window title, no package | unguarded path after seeing it, buttons by colour |
| notification banner covers the top bar | a chat app posted a heads-up | swipe it away, then re-locate `交卷` |

## Evidence

The raw field notes behind the numbers above (per-question y samples, the three
dialogs, the seven answers a bad batch corrupted, the 50-point submission that
skipped verification) are kept in
[field-notes-2026-09-29.md](field-notes-2026-09-29.md).
