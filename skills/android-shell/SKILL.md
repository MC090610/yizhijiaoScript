---
name: android-shell
description: Drive this Android phone from Termux at shell (uid 2000) level through Shizuku's rish - screencap, uiautomator UI dumps, input tap/swipe/text, app launch, package and dumpsys queries. Use when a task must read or control the Android device itself rather than the Termux/Linux side. Not for plain Termux file, package, or code work.
metadata:
  short-description: Control this Android phone from Termux via Shizuku
---

# Android Shell (Shizuku / rish)

Drive the phone this Termux runs on at **shell (uid 2000)** level using Shizuku's
`rish`. This is the ADB-equivalent channel: screenshots, UI hierarchy, touch and
text injection, app launch, and `pm`/`dumpsys`/`wm` queries.

Use it when a task must read or control the **device itself**. For Termux/Linux
files, packages, or code, just work normally.

## Hard rules: user data is off-limits

These override everything else in this skill.

**Never delete, move, overwrite, rename or truncate** any of the following unless
the user explicitly asked for that specific item:

- Photos and videos, anywhere: `/sdcard/DCIM`, `Pictures`, `Movies`, `Download`,
  `Android/media`, and any MediaStore row.
- SMS / MMS / call logs: MediaStore and Telephony providers, `mmssms.db`,
  `/data/data/com.android.providers.telephony`, `/data/user/...`.
- Any other file belonging to the user, including app-private data
  (`/data/data/<pkg>/...`, `/sdcard/Android/data/<pkg>/...`).

**Never clean up on your own initiative.** No "freeing space", "clearing cache",
"removing old files", and no sweeping by pattern, by age, or by directory. Leave
the recycle bin (`.Trash`, `MIUI/Gallery/cloud/.trashBin`) alone unless asked.

**When the user does ask for a deletion, the list is the contract:**

- Delete exactly the items named - no globs beyond what they wrote, no "related"
  files, no directories they did not name, no expanding the scope.
- If the scope is at all ambiguous, print the exact paths and count first and
  confirm; never widen it on your own.
- Afterwards, report exactly what was removed and whether it is recoverable.
- The only exception is droid's own scratch files (`.droid_*` under `/sdcard`),
  which droid creates and removes as part of normal operation.

`droid.sh` enforces this in code: any `rm`/`mv`/`shred`/`truncate`/`-delete`/
`content delete`/`pm clear` command that touches `/sdcard`, `content://`, `/data`
or an album name is **refused** unless `DROID_ALLOW_DESTRUCTIVE=1` is set. Only set
that after the user has confirmed the exact items. Reading needs no flag, but see
"Media and files" for the privacy expectations that go with it.

## Environment (already set up)

- Redmi Note 14 Pro+ (`24115RA8EC`), Android 16 / SDK 36, no root.
- Screen `1220x2712`, density 480.
- Termux app id `com.termux` (uid 10278). `rish` and `rish_shizuku.dex` live in `$HOME`.
- Shizuku 13.6.0, started via wireless debugging. `RISH_APPLICATION_ID=com.termux` is exported in `~/.bashrc`.

## The one failure mode to know

Shizuku's app process gets **frozen** (Android 16 cached-app freezer / HyperOS),
and a frozen Shizuku cannot answer the binder request. `rish` then fails with a
fixed **5-second `Request timeout`** even though the Shizuku UI still says it is
running and battery optimization is already unrestricted.

`scripts/droid.sh` handles this: on a timeout it launches Shizuku's main activity
to wake the process and retries once. If it still times out, open the Shizuku app
by hand and retry. Do not conclude "Shizuku is not running" from the timeout
alone, and do not try to detect it via `service list` - Shizuku 12+ does not
register a ServiceManager entry.

## Use the helper

```bash
scripts/droid.sh check                 # verify rish (prints id) and auto-wake if needed
scripts/droid.sh sh 'getprop ro.product.model'
scripts/droid.sh focus                 # current focused window/app
scripts/droid.sh size                  # screen size + density
scripts/droid.sh shot ~/a.png          # screenshot (default ~/droid-<ts>.png)
scripts/droid.sh ui                    # dump UI hierarchy; lists text/EditText nodes with bounds
scripts/droid.sh tap 1012 202          # tap
scripts/droid.sh swipe 500 1500 500 500 300
scripts/droid.sh key BACK              # HOME/BACK/ENTER, or a numeric keycode
scripts/droid.sh text "hello"          # type into the focused field
scripts/droid.sh open com.tencent.mm   # launch an app
scripts/droid.sh apps tencent          # list matching packages
```

A symlink is installed at `~/bin/droid`, so plain `droid <cmd>` works in Termux.

## Working recipes

**Find where to tap.** Do not guess pixels. Run `droid ui`, read the node whose
`text`/`content-desc`/`resource-id` you want, take its `bounds="[x1,y1][x2,y2]"`
and tap the center: `droid tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 ))`.

`uiautomator dump` waits for an idle window, so it fails with `could not get idle
state` while a constantly redrawing app is in front (a terminal, video, animations)
- including Codex's own TUI. Switch to a static screen first (`droid key HOME`) and
retry; when dumping an app, make sure that app is the focused window.

**Look at the screen.** `droid shot`, then view the PNG file to see the result.
Take a screenshot before and after an action to confirm what changed.

**Type into a field.** Tap it first (or confirm it is `focused="true"` in `droid ui`),
then `droid text "..."`. Spaces are converted to `%s`, which `input text` expects.
Non-ASCII text is unreliable through `input text`; keep injected text ASCII, or use
`droid sh "am broadcast ..."` with an IME if Chinese input is genuinely required.

**Launch an app.** Use `droid open <package>` (it runs `monkey -p ... LAUNCHER 1`).
Guessing `pkg/.SomeActivity` names is unreliable - prefer this.

## Status notifications and the dynamic island

`droid notify "TITLE" "TEXT"` posts a one-off normal notification from
`com.android.shell`. For a running task, use the status pipeline instead:

```bash
droid status "正在跑测试"     # working; posts/updates only while Termux is not focused
droid done "全部用例通过"     # finished; short alerting message (Mi Band reaches this)
droid watch start|stop|status # the watcher daemon
```

The watcher polls the focused window every 3s and keeps the notification in sync:
Termux not focused (a locked screen counts as background) - post/update the text;
Termux focused again while still working - cancel; state `done` - keep showing the
message regardless of focus. Two ticks of foreground are required before cancelling,
so a brief screen wake does not make the notice flap. State lives in
`~/.droid_status`, the daemon in `~/.droid_watch.pid`, activity in
`~/.droid_watch.log`.

Two channels, because they need different alerting:

| state | channel | importance | purpose |
|---|---|---|---|
| `status` | `droid_status` ("Codex 进行中") | 2 / LOW, silent | progress, safe to update often |
| `done` | `droid_done` ("Codex 已完成") | 3 / DEFAULT, alerts | the one a Mi Band mirrors and buzzes for |

`done` text is trimmed to 20 characters so it stays readable on the band - keep
the message short. If the phone's own progress updates should never reach the band,
mute the "Codex 进行中" channel in system settings; the done channel is separate.

For a one-off message that is not tied to a task state, use `droid tell "..."`
(same alerting channel, own notification id so it does not fight the status
notice). It is trimmed to 20 characters by default for the band; when the message
is really meant for the phone screen, raise the cap:

```bash
droid tell "任务已完成"                  # <= 20 chars, band-friendly
droid tell -n 50 "仓库已推送，练习内容已脱敏，本机清理完毕"   # longer, phone
```

Notifications are attributed to **com.termux** (not `com.android.shell`), which is
what the `scripts/termux_notify` helper is for - see the next section.

### Why the notification helper exists

Termux has no notification API of its own: `termux-api` commands need the
`com.termux.api` app, which is not installed, and the official APK is
signature-incompatible with ZeroTermux. The main app exposes no way to post a
notification either. So the skill ships `scripts/termux_notify/DroidNotify.java`,
compiled by `scripts/build-helper.sh` (`pkg install openjdk-21 d8`) into
`droid-notify.jar`, and launched through `app_process` exactly like Termux's own
`am` wrapper:

```
CLASSPATH=droid-notify.jar app_process -Xnoimage-dex2oat / DroidNotify post TITLE TEXT
```

Two gotchas are baked into it:

- `ActivityThread.systemMain()` needs `Looper.prepareMainLooper()` first.
- A `NotificationManager` obtained from `createPackageContext("com.termux")` still
  reports `getOpPackageName() == "android"`, and MIUI rejects the post with
  "Permission Denied to post local notification for android". The helper therefore
  calls `INotificationManager.enqueueNotificationWithTag` directly, passing
  `com.termux` as both `pkg` and `opPkg`.

Without the helper, `droid` falls back to `cmd notification post`
(`com.android.shell`) and approximates "cancel" with `cmd notification snooze`.

### The dynamic island

The island only renders *focus notifications* - notifications whose extras carry a
`miui.focus.param` Bundle. `dumpsys notification` shows this as `focusType=...`.
The helper has a `--focus` flag that adds those extras, but it is **off by default
and unverified**: MIUI may require the app to be granted 焦点通知 in settings, and
`cmd notification post` can never set extras (nor can Termux's own ongoing
notification reach the island). The device does expose a `dynamic_island` service
(`miui.dynamicisland.IDynamicIslandService`) but it is not usable via
`service call`, so it is not a shortcut.

## Locked / screen-off operation

This is the normal way the phone is used while a task runs, and it works:

- Termux processes keep running (a 22s ticker under a locked screen lost zero
  ticks), and `rish` keeps working (`rish -c id` returned in ~0.7s while dozing).
- Notifications still post. For the watcher, a locked screen counts as background:
  `mCurrentFocus` becomes `NotificationShade`, so it posts instead of cancelling.
- `screencap` returns a blank/black frame while the display is off, and
  `uiautomator dump` fails with `could not get idle state` on an animating keyguard.
  Do not try to read the screen while it is locked.

One caveat seen on this device: a bound Mi Band can wake/unlock the phone, which
brings Termux back to the foreground and therefore cancels the notification - that
is the intended behaviour, not a bug.

## Media and files

- Termux itself reads shared storage directly: `~/storage/shared` (= `/sdcard`)
  covers `DCIM`, `Pictures`, `Movies` and `Download`. No shell involved.
- Through the shell you additionally reach the app media dirs that Termux cannot
  see on Android 11+: `/sdcard/Android/data/<pkg>/...` (WeChat `MicroMsg/`, QQ
  `Tencent/`, ...).
- `droid media [images|videos|all] [N]` lists the newest MediaStore rows with
  name, relative path, `date_added` and dimensions; `droid media all` uses the
  generic file table.
- `droid pull <device-path> [local-path]` copies a file off the device. Shared
  storage is copied directly; anything else is staged through
  `/sdcard/Download` by the shell, because piping large binaries through `rish`
  stdout corrupts them.
- Access is read *and* write (the shell can create or delete under `/sdcard`), so
  the usual care applies: never delete or move the user's media.

This is the user's personal data. Read only what the task actually needs, do not
browse the gallery out of curiosity, do not render personal photos into the
conversation unless the user asks for that specific image, and delete any copies
you make (or say where they are).

## Safety: this acts on the real device

Injected input is indistinguishable from the user's own. Reading (screencap,
`droid ui`, `dumpsys`) is harmless, but tapping and typing can trigger real
actions. Specifically:

- Typing into a field is fine; **do not press send/submit** (chat messages, forms,
  purchases, confirmations, deleting data) unless the user explicitly asks for that
  exact action.
- Prefer non-destructive targets (a search field, a draft) over sending to people.
- Clean up: delete screenshots and UI dumps you created when done, especially ones
  showing private content.

## Other channels

- `adb` (android-tools 37.0.0) is installed but needs a wireless-debugging
  pairing, so prefer `rish`. When calling it from inside Codex, prefix with
  `env -u LD_LIBRARY_PATH` - Codex's launcher points `LD_LIBRARY_PATH` at a
  bundled older `libc++_shared.so` that breaks `adb`'s dynamic linking.
- `am` (termux-am) can start activities without Shizuku; `pm`/`cmd` run as the app
  uid and are mostly permission-limited. Neither can inject input or capture the
  screen - that needs shell, i.e. `rish`.

## Moving to another (Xiaomi) phone, or a fresh session

Nothing here is tied to a session: the skill folder plus `~/bin/droid` and the
built helper persist on disk, so a new Codex session can call `droid` directly.
Run `droid setup` to see what is present and what is missing.

Portable as-is (no changes needed on another device):

- `rish` shell access, `screencap`, `uiautomator`, `input`, `am`/`monkey`.
- `scripts/termux_notify` - the helper detects the host package from the process
  uid (`PackageManager.getPackagesForUid`), falling back to `com.termux`, so it
  works for Termux, ZeroTermux or any fork. Override with `DROID_NOTIFY_PKG`.
- The watcher's foreground detection tries `ResumedActivity`, then
  `mResumedActivity`, then `mCurrentFocus`.
- The MIUI/HyperOS quirks baked into the helper (`Looper.prepareMainLooper()`
  before `ActivityThread.systemMain()`; calling `INotificationManager`
  directly with `pkg == opPkg` to get past "Permission Denied to post local
  notification for android").

Must be redone per device:

1. Install and start Shizuku (wireless debugging), then get `rish` and
   `rish_shizuku.dex` into `$HOME` (or point `$RISH` at them). This is the one
   hard dependency.
2. `pkg install openjdk-21 d8` and run `scripts/build-helper.sh`. The resulting
   jar is plain dex and can also be copied between devices.
3. `mkdir -p ~/bin && ln -s <skill>/scripts/droid.sh ~/bin/droid`, and add
   `~/bin` to `PATH` in `~/.bashrc`.
4. Grant the terminal app notification permission (and, if wanted, enable
   焦点通知 on its notification channel for the island).
5. Verify: `droid setup` (all green), then `droid shot ~/t.png` and
   `droid notify "Codex" "hi"`.

Device facts quoted elsewhere in this file (`1220x2712`, model `24115RA8EC`) are
for the reference phone only - use `droid size` and `droid apps` on a new one.
Expect the same two Xiaomi behaviours: the app freezer can stop Shizuku (the
wrapper auto-wakes it), and MIUI may silently block background activity starts,
so `droid open <pkg>` can appear to do nothing until the user switches manually.
