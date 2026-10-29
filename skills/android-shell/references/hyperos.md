# HyperOS / MIUI notes (OEM layer only)

Reference device: **Redmi Note 14 Pro+ (`24115RA8EC`)**, **HyperOS 3.0**
(`OS3.0.305.0.WOPCNXM`, MIUI UI `V816`), Android 16 / SDK 36, no root.

Everything here is about what the **Xiaomi layer** adds on top of AOSP. Generic
`rish` / `droid` mechanics stay in `SKILL.md`; keep this file for the OEM quirks
so the main skill still works on a Pixel or a Samsung.

Measured on the reference device on 2026-10-29 unless marked *unverified*.

---

## 1. Shizuku gets frozen (the #1 failure)

**Symptom** - `rish` fails after a fixed ~5 s with `Request timeout`, while:

- the Shizuku app still shows "running";
- battery optimisation is already "无限制";
- `service list` has no Shizuku entry (Shizuku 12+ does not register one).

**Cause** - Android 16 cached-app freezer plus HyperOS' own app policy.

**Fix** - `droid.sh` wakes Shizuku (starts its `MainActivity`) on a timeout and
retries once. If it still times out, open the Shizuku app by hand.

**Screen-off wrinkle** - the auto-wake starts an activity from the background,
which HyperOS may block (section 2). If `droid check` fails while the screen is
off: `droid key 224` (wake) → retry → if it still fails, ask the user to unlock.

---

## 2. Background activity starts are blocked

`am start` / `monkey -p <pkg> -c android.intent.category.LAUNCHER 1` can return
success while the app never comes to the front. `droid open` therefore "does
nothing" sometimes.

- Always confirm with `droid focus` instead of assuming it worked.
- Do not loop `droid open` - if two attempts fail, ask the user to switch apps.
- If hands-off launching matters, the user can grant the terminal app
  **后台弹出界面 / 显示在其他应用上层** (PEM settings); the skill must not flip
  those permissions itself.

---

## 3. Notifications

Three separate traps, all handled by `scripts/termux_notify`:

| trap | detail | handling |
|---|---|---|
| wrong op package | `NotificationManager` from a `createPackageContext("com.termux")` still reports `getOpPackageName() == "android"`; MIUI rejects with *"Permission Denied to post local notification for android"* | call `INotificationManager.enqueueNotificationWithTag` with `pkg == opPkg == com.termux` |
| `systemMain()` crash | `ActivityThread.systemMain()` needs a prepared looper | `Looper.prepareMainLooper()` first |
| no island | the dynamic island only renders **focus notifications** (extras carry `miui.focus.param`; `dumpsys notification` shows `focusType=...`) | `--focus` flag, off by default and *unverified*; the channel also needs 焦点通知 granted |

Channels: `droid_status` (LOW, silent progress) and `droid_done` (DEFAULT,
alerts, mirrored by a Mi Band). `cmd notification post` always posts as
`com.android.shell`, cannot set extras, and therefore can never reach the island.

When the screen locks, `mCurrentFocus` becomes `NotificationShade`, so the watcher
treats "locked" as "background" and posts instead of cancelling - that is correct.
A paired Mi Band waking/unlocking the phone moves Termux back to the foreground
and cancels the progress notice; that is also correct.

---

## 4. Screen-off / keyguard matrix

```bash
droid sh 'dumpsys power | grep -m1 mWakefulness='                          # Awake | Asleep | Dozing
droid sh 'dumpsys window | grep -m2 -E "isKeyguardShowing|mDreamingLockscreen"'
```

| operation | screen on + unlocked | screen off / keyguard |
|---|---|---|
| `rish`, `dumpsys`, `pm`, `am` | works | works |
| `droid status/done/tell` | works | works |
| `screencap` / `droid shot` | works | blank/black frame |
| `uiautomator dump` / `droid ui` | works on a static screen | fails on an animating keyguard |
| `input tap/swipe/text` | works | injected, but lands on the keyguard |

Wake only, never toggle:

```bash
droid key 224     # KEYCODE_WAKEUP - wakes, never sleeps
droid key 26      # KEYCODE_POWER - toggles; turns the screen OFF if already on. Avoid.
```

---

## 5. Unlocking

- Check first: `dumpsys window | grep -m1 isKeyguardShowing` (`false` = usable).
- **Non-secure** keyguard (swipe only): `droid key 82` (MENU) sometimes dismisses
  it; otherwise `droid swipe 600 2200 600 700 300` to swipe up.
- **Secure** keyguard (PIN / pattern / password): there is no shell-side bypass.
  Ask the user to unlock, or let a trusted Bluetooth device (Mi Band) do it.
- Never try to guess or brute-force a code, and never type a PIN you found in a
  file.

---

## 6. One-time settings checklist

Only needed once per device, and only where a hands-off workflow is wanted:

- 通知权限 for the terminal app (otherwise `droid status/done` silently fail).
- 焦点通知 on the channel (only if the dynamic island should show progress).
- 省电策略 = **无限制** for Shizuku and the terminal app (helps, but does *not*
  stop the freezer - the wrapper's auto-wake is still required).
- 自启动 for Shizuku and the terminal app.
- 后台弹出界面 / 显示在其他应用上层, only if `droid open` must work without the
  user's hand.
- Wireless debugging must be re-paired after a reboot before Shizuku starts again.

---

## 7. Diagnostics cheat sheet

```bash
droid sh 'getprop ro.mi.os.version.name; getprop ro.mi.os.version.incremental; getprop ro.miui.ui.version.name'
droid sh 'dumpsys power | grep -m1 mWakefulness='
droid sh 'dumpsys window | grep -m2 -E "isKeyguardShowing|mDreamingLockscreen"'
droid focus                                  # which app is actually in front
droid check                                  # rish round-trip + auto-wake
droid sh 'dumpsys notification | grep -m5 -E "focusType|pkg="'
```

---

## 8. Portability

- Moving to a **non-Xiaomi** phone: ignore this file, keep `SKILL.md`.
- Moving to another **Xiaomi** phone: the list above is the baseline; verify the
  model/OS first with the diagnostic block, because HyperOS versions rename
  settings (e.g. PEM instead of MIUI's old "后台弹出界面").
