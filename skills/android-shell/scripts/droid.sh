#!/data/data/com.termux/files/usr/bin/bash
# droid - drive this Android device from Termux at shell (uid 2000) level via Shizuku.
# Run `droid help` for usage.
set -uo pipefail

export RISH_APPLICATION_ID="${RISH_APPLICATION_ID:-com.termux}"
SHIZUKU_MAIN="moe.shizuku.privileged.api/moe.shizuku.manager.MainActivity"

# ${#var} must count characters, not bytes, for the 20-char message cap.
case "${LC_ALL:-${LANG:-}}" in
  *UTF-8*|*utf8*|*UTF8*) ;;
  *) export LC_ALL=C.UTF-8 ;;
esac

SELF="$0"
[ -L "$SELF" ] && SELF="$(readlink -f "$SELF" 2>/dev/null || printf '%s' "$SELF")"
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"

TITLE="${DROID_NOTIFY_TITLE:-Codex}"
TAG="codex_status"
MSG_ID="${DROID_MSG_ID:-4212}"
STATE_FILE="${DROID_STATE_FILE:-$HOME/.droid_status}"
PID_FILE="$HOME/.droid_watch.pid"
LOG_FILE="$HOME/.droid_watch.log"
INTERVAL="${DROID_WATCH_INTERVAL:-3}"

die() { printf 'droid: %s\n' "$*" >&2; exit 1; }

# Refuse destructive commands aimed at user data unless the user explicitly
# asked for that exact deletion (then re-run with DROID_ALLOW_DESTRUCTIVE=1).
# droid's own scratch files under /sdcard (.droid_*) are exempt.
guard_destructive() {
  local cmd="$1" flat
  flat="$(printf '%s' "$cmd" | sed -E 's#/sdcard/[^ ]*\.droid_[A-Za-z0-9_.]*# #g')"
  printf '%s' "$flat" | grep -qE \
    '(^|[^A-Za-z])(rm|mv|shred|truncate|rmdir)([[:space:]]|$)|content[[:space:]]+delete|pm[[:space:]]+clear|settings[[:space:]]+delete|[[:space:]]-delete|dd[[:space:]]+if=' \
    || return 0
  printf '%s' "$flat" | grep -qE \
    '/sdcard|/storage/emulated|content://|/data/data|/data/user|DCIM|Pictures|Movies|Download|mmssms|telephony|SMS' \
    || return 0
  [ "${DROID_ALLOW_DESTRUCTIVE:-0}" = "1" ] && return 0
  printf 'droid: BLOCKED - this looks like it deletes or moves user data.\n' >&2
  printf 'droid:   %s\n' "$cmd" >&2
  printf 'droid: photos/albums (DCIM, Pictures, Movies, Download), SMS/call logs and\n' >&2
  printf 'droid: app-private files must never be touched without the user asking for\n' >&2
  printf 'droid: that specific item. Re-run with DROID_ALLOW_DESTRUCTIVE=1 only after\n' >&2
  printf 'droid: the user confirmed, and delete exactly the items they named.\n' >&2
  return 1
}

locate_rish() {
  local c
  for c in "${RISH:-}" "$HOME/rish" "${PREFIX:-}/bin/rish"; do
    if [ -n "$c" ] && [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}
RISH="$(locate_rish)" || die "cannot find 'rish'; set \$RISH to its full path"

# The terminal app's own package name, used to tell "user is looking at the
# terminal" from "user is elsewhere". Derived from our uid so the skill is not
# tied to com.termux specifically.
detect_term_pkg() {
  [ -n "${DROID_TERM_PKG:-}" ] && { printf '%s' "$DROID_TERM_PKG"; return 0; }
  local uid pkg
  uid="$(id -u 2>/dev/null)"
  if [ -n "$uid" ] && command -v cmd >/dev/null 2>&1; then
    pkg="$(cmd package list packages -U 2>/dev/null |
      grep -m1 " uid:$uid\$" | sed 's/^package://; s/ uid:.*//')"
    [ -n "$pkg" ] && { printf '%s' "$pkg"; return 0; }
  fi
  printf 'com.termux'
}
TERM_PKG="$(detect_term_pkg)"

# Path to the compiled termux-notify helper, when it has been built.
helper_jar() {
  local c
  for c in "${DROID_NOTIFY_JAR:-}" "$SCRIPT_DIR/termux_notify/droid-notify.jar"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# Launch Shizuku's UI to unfreeze its process (it cannot answer while frozen).
wake() {
  command -v am >/dev/null 2>&1 && am start -n "$SHIZUKU_MAIN" >/dev/null 2>&1
  sleep 1
}

# Run a remote shell command; on a Shizuku timeout, wake once and retry.
run() {
  local out
  guard_destructive "$1" || return 1
  out="$("$RISH" -c "$1" 2>&1)"
  if [[ "$out" == *"Request timeout"* || "$out" == *"not running"* ]]; then
    wake
    out="$("$RISH" -c "$1" 2>&1)"
  fi
  printf '%s\n' "$out"
  case "$out" in
    *"Request timeout"*|*"not running"*)
      printf 'droid: Shizuku is not answering. Open the Shizuku app, then retry.\n' >&2
      return 1 ;;
  esac
  return 0
}

# Single-quote a string for the remote shell.
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

screenshot() {
  local dest="${1:-$HOME/droid-$(date +%Y%m%d-%H%M%S).png}"
  run "screencap -p /sdcard/.droid_shot.png" >/dev/null 2>&1 || die "screencap failed"
  cp /sdcard/.droid_shot.png "$dest" || die "could not copy screenshot to $dest"
  run "rm -f /sdcard/.droid_shot.png" >/dev/null 2>&1
  printf '%s\n' "$dest"
}

ui_dump() {
  local dest="${1:-$HOME/droid-ui.xml}"
  run "uiautomator dump /sdcard/.droid_ui.xml" >/dev/null 2>&1
  cp /sdcard/.droid_ui.xml "$dest" 2>/dev/null || true
  run "rm -f /sdcard/.droid_ui.xml" >/dev/null 2>&1
  [ -s "$dest" ] || die "uiautomator dump produced nothing: uiautomator waits for an idle
window, so it fails with 'could not get idle state' when the foreground UI keeps
redrawing (a terminal/Codex TUI, video, animations). Switch to a static screen and
retry; the screen being off also fails. 'droid key HOME' gives a static screen."
  printf '# %s\n' "$dest"
  printf '%-24s %-16s %s\n' BOUNDS CLASS TEXT
  tr '>' '\n' < "$dest" | grep -E '^<node' | while IFS= read -r n; do
    local cls text desc rid bounds
    cls=$(printf '%s' "$n" | sed -E 's/.* class="([^"]*)".*/\1/')
    text=$(printf '%s' "$n" | sed -E 's/.* text="([^"]*)".*/\1/')
    desc=$(printf '%s' "$n" | sed -E 's/.* content-desc="([^"]*)".*/\1/')
    rid=$(printf '%s' "$n" | sed -E 's/.* resource-id="([^"]*)".*/\1/')
    bounds=$(printf '%s' "$n" | sed -E 's/.* bounds="([^"]*)".*/\1/')
    if [ -n "$text" ] || [ -n "$desc" ] || [[ "$cls" == *EditText* ]]; then
      printf '%-24s %-16s %s%s%s\n' "$bounds" "${cls##*.}" "$text" \
        "${desc:+  <$desc>}" "${rid:+  [$rid]}"
    fi
  done
}

# Post a plain notification (appears in the shade). This does NOT reach the
# HyperOS dynamic island - see SKILL.md for why and what that requires.
notify() {
  [ $# -ge 2 ] || die 'usage: droid notify "TITLE" "TEXT" [TAG]'
  local title="$1" text="$2" tag="${3:-droid}"
  run "cmd notification post -t $(sq "$title") $(sq "$tag") $(sq "$text")" >/dev/null
  printf 'posted notification: %s / %s\n' "$title" "$text"
}

# --- status notification ---------------------------------------------------

# Post/update the status notification. Uses the termux-notify helper (so the
# notification is attributed to com.termux) when available, otherwise falls
# back to `cmd notification post` (com.android.shell).
notify_post() {  # $1 text, $2 = "alert" for an alerting (band-reaching) notification
  local text="$1" alert="${2:-}" jar
  if jar="$(helper_jar)"; then
    env -u LD_LIBRARY_PATH -u LD_PRELOAD CLASSPATH="$jar" \
      /system/bin/app_process -Xnoimage-dex2oat / DroidNotify post \
      ${alert:+--alert} "$TITLE" "$text"
    return $?
  fi
  run "cmd notification post -t $(sq "$TITLE") $TAG $(sq "$text")" >/dev/null 2>&1
}

# Trim to N characters so the message stays readable on a Mi Band.
truncate_chars() {
  local s="$1" n="${2:-20}"
  [ -n "$s" ] || return 0
  if [ "${#s}" -le "$n" ]; then printf '%s' "$s"; else printf '%s' "${s:0:$n}"; fi
}

# droid tell "短消息" - push a short alerting message to the user (reaches the
# Mi Band). Uses its own notification id so it does not fight the status notice.
tell() {
  # Default cap suits a Mi Band; -n raises it for phone-only notices.
  local max="${DROID_MSG_MAX:-20}"
  if [ "${1:-}" = "-n" ] && [ $# -ge 2 ]; then max="$2"; shift 2; fi
  [ $# -gt 0 ] || die 'usage: droid tell [-n N] "message"'
  local msg jar
  msg="$(truncate_chars "$*" "$max")"
  if jar="$(helper_jar)"; then
    env -u LD_LIBRARY_PATH -u LD_PRELOAD CLASSPATH="$jar" DROID_NOTIFY_ID="$MSG_ID" \
      /system/bin/app_process -Xnoimage-dex2oat / DroidNotify post --alert "$TITLE" "$msg"
  else
    run "cmd notification post -t $(sq "$TITLE") droid_msg $(sq "$msg")" >/dev/null 2>&1
  fi
  printf 'told the user: %s\n' "$msg"
}

# --- media ------------------------------------------------------------------

# droid media [images|videos|all] [N] - newest entries from MediaStore.
media() {
  local kind="${1:-images}" n="${2:-10}" uri
  case "$kind" in
    images|image) uri="content://media/external/images/media" ;;
    videos|video) uri="content://media/external/video/media" ;;
    all) uri="content://media/external/file/media" ;;
    *) die "usage: droid media [images|videos|all] [N]" ;;
  esac
  run "content query --uri $uri \
--projection _display_name:relative_path:date_added:width:height \
--sort $(sq 'date_added DESC') 2>/dev/null | head -n $n"
}

# droid pull <device-path> [local-path] - copy a file off the device.
# Shared storage is readable by Termux directly; anything else (/data, app
# private dirs) is staged through /sdcard by the shell.
pull() {
  local src="$1" dest="${2:-}" stage="/sdcard/Download/.droid_pull.$$"
  [ -n "$src" ] || die 'usage: droid pull <device-path> [local-path]'
  [ -n "$dest" ] || dest="$HOME/$(basename "$src")"
  if [ -r "$src" ]; then
    cp -- "$src" "$dest" || die "cannot copy $src"
  else
    run "cp $(sq "$src") $(sq "$stage")" >/dev/null 2>&1 ||
      die "cannot read $src (tried direct and via shell)"
    cp "$stage" "$dest" || die "cannot write $dest"
    run "rm -f $(sq "$stage")" >/dev/null 2>&1
  fi
  printf '%s\n' "$dest"
}

# With the helper this is a real cancel. Without it there is no way to remove a
# shell notification, so snooze it out of the shade instead.
notify_cancel() {
  local jar key
  if jar="$(helper_jar)"; then
    env -u LD_LIBRARY_PATH -u LD_PRELOAD CLASSPATH="$jar" \
      /system/bin/app_process -Xnoimage-dex2oat / DroidNotify cancel >/dev/null 2>&1
    return 0
  fi
  key="$(run 'cmd notification list' 2>/dev/null | grep -m1 "com.android.shell.*$TAG" | cut -d'|' -f1-5)"
  [ -n "$key" ] && run "cmd notification snooze --for 86400000 $(sq "$key")" >/dev/null 2>&1
  return 0
}

read_state() {
  state=""
  text=""
  [ -f "$STATE_FILE" ] || return 0
  state="$(sed -n 1p "$STATE_FILE" 2>/dev/null)"
  text="$(sed -n '2,$p' "$STATE_FILE" 2>/dev/null)"
}

set_state() {
  printf '%s\n%s\n' "$1" "$2" > "$STATE_FILE"
}

watcher_pid() {
  [ -f "$PID_FILE" ] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && { printf '%s' "$pid"; return 0; }
  return 1
}

ensure_watcher() {
  watcher_pid >/dev/null && return 0
  setsid "$SELF" __watch >>"$LOG_FILE" 2>&1 &
  printf '%s\n' "$!" > "$PID_FILE"
  sleep 1
}

stop_watcher() {
  local pid
  if pid="$(watcher_pid)"; then
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    sleep 1
    kill -KILL -- "-$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
}

# The daemon: watch the foreground app and keep the notification in sync.
watch_loop() {
  printf '%s watcher started (pid %s)\n' "$(date '+%F %T')" "$$" >>"$LOG_FILE"
  local line fg state text want_text want_shown want_alert last="" shown=0 fg_ticks=0
  while :; do
    # ResumedActivity is the AOSP/MIUI field; fall back to window focus on ROMs
    # that do not print it.
    "$RISH" -c "while :; do dumpsys activity activities 2>/dev/null | grep -m1 ResumedActivity || dumpsys window 2>/dev/null | grep -m1 mCurrentFocus; sleep $INTERVAL; done" 2>/dev/null |
    while IFS= read -r line; do
      # Debounce: a brief foreground flash (screen waking for a moment) must not
      # cancel the notification, otherwise the notice flaps.
      case "$line" in
        *"$TERM_PKG"*) fg_ticks=$((fg_ticks + 1)) ;;
        *) fg_ticks=0 ;;
      esac
      [ "$fg_ticks" -ge 2 ] && fg=1 || fg=0
      read_state
      if [ -z "$state" ]; then
        want_shown=0; want_text=""; want_alert=""
      elif [ "$state" = done ]; then
        # Alerting on purpose: this is the one the Mi Band should buzz for.
        want_shown=1; want_text="$(truncate_chars "$text" 20)"; want_alert=alert
      elif [ "$fg" = 1 ]; then
        want_shown=0; want_text=""; want_alert=""
      else
        want_shown=1; want_text="$text"; want_alert=""
      fi
      if [ "$want_shown" = 1 ]; then
        if [ "$want_text" != "$last" ]; then
          printf '%s post: %s\n' "$(date '+%T')" "$want_text" >>"$LOG_FILE"
          notify_post "$want_text" "$want_alert" >>"$LOG_FILE" 2>&1
          last="$want_text"; shown=1
        fi
      elif [ "$shown" = 1 ]; then
        printf '%s cancel\n' "$(date '+%T')" >>"$LOG_FILE"
        notify_cancel
        shown=0; last=""
      fi
    done
    printf '%s foreground stream ended, restarting\n' "$(date '+%T')" >>"$LOG_FILE"
    wake
  done
}

usage() {
  cat <<'EOF'
droid - drive this Android device from Termux via Shizuku (shell uid 2000)

  droid check                 verify rish works (prints id)
  droid wake                  launch the Shizuku app to unfreeze it
  droid sh <cmd>              run a raw shell command
  droid focus                 current focused window/app
  droid size                  screen size and density
  droid shot [file]           screenshot (default ~/droid-<timestamp>.png)
  droid ui [file]             dump UI hierarchy; list text/EditText nodes with bounds
  droid tap X Y               tap at coordinates
  droid taps on|off           show a touch indicator where injected taps land
  droid swipe X1 Y1 X2 Y2 [MS]
  droid key KEYCODE           e.g. HOME, BACK, ENTER, or a numeric keycode
  droid text "STRING"         type into the focused field (never presses send)
  droid open PACKAGE          launch an app, e.g. com.tencent.mm
  droid apps [PATTERN]        list packages
  droid media [images|videos|all] [N]   newest gallery entries (MediaStore)
  droid pull <device-path> [local]      copy a file off the device
  droid notify "T" "MSG" [TAG]  post a notification (shade only, not the island)
  droid status "TEXT"         set the working status (background notification + auto watcher)
  droid done "TEXT"           finished: alerting short message (<=20 chars, reaches the band)
  droid tell "TEXT"           push a short alerting message (<=20 chars, reaches the band)
  droid watch start|stop|status   manage the status watcher daemon
  droid setup                 show what this device has and what is missing
EOF
}

main() {
  local cmd="${1:-help}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    help|-h|--help) usage ;;
    wake) wake; run 'id' ;;
    check) run 'id' ;;
    sh|shell) [ $# -gt 0 ] || die "usage: droid sh <command>"; run "$*" ;;
    focus|current) run 'dumpsys window | grep -E "mCurrentFocus|mFocusedApp"' ;;
    size) run 'wm size; wm density' ;;
    shot|screenshot) screenshot "${1:-}" ;;
    ui|dump) ui_dump "${1:-}" ;;
    tap) [ $# -eq 2 ] || die "usage: droid tap X Y"; run "input tap $1 $2" ;;
    taps)
      case "${1:-on}" in
        on|1)  run 'settings put system show_touches 1' >/dev/null
               printf 'touch indicator: on\n' ;;
        off|0) run 'settings put system show_touches 0' >/dev/null
               printf 'touch indicator: off\n' ;;
        *) die 'usage: droid taps on|off' ;;
      esac ;;
    swipe) [ $# -ge 4 ] || die "usage: droid swipe X1 Y1 X2 Y2 [MS]"
           run "input swipe $1 $2 $3 $4 ${5:-300}" ;;
    key) [ $# -eq 1 ] || die "usage: droid key KEYCODE"; run "input keyevent $1" ;;
    text|type) [ $# -eq 1 ] || die "usage: droid text \"STRING\""
               run "input text $(sq "${1// /%s}")" ;;
    open|launch) [ $# -eq 1 ] || die "usage: droid open PACKAGE"
                 run "monkey -p $1 -c android.intent.category.LAUNCHER 1" | tail -n 1 ;;
    apps) run 'pm list packages' | grep -i "${1:-}" ;;
    media) media "${1:-images}" "${2:-10}" ;;
    pull) [ $# -ge 1 ] || die 'usage: droid pull <device-path> [local-path]'
          pull "$1" "${2:-}" ;;
    notify) notify "$@" ;;
    tell|msg|say) tell "$@" ;;
    status) [ $# -gt 0 ] || die 'usage: droid status "TEXT"'
            set_state working "$*"; ensure_watcher
            printf 'status: %s\n' "$*" ;;
    done) set_state done "$*"; ensure_watcher
          printf 'done: %s\n' "$*" ;;
    watch)
      case "${1:-status}" in
        start) set_state "${DROID_STATE_DEFAULT_WORKING:-working}" "${2:-Codex 正在干活}"
               ensure_watcher; printf 'watcher pid %s\n' "$(cat "$PID_FILE")" ;;
        stop) stop_watcher; notify_cancel; rm -f "$STATE_FILE"
              printf 'watcher stopped\n' ;;
        status|"") if watcher_pid >/dev/null; then
                     printf 'watcher running (pid %s)\n' "$(cat "$PID_FILE")"
                     read_state; printf 'state=%s text=%s\n' "$state" "$text"
                   else
                     printf 'watcher not running\n'
                   fi ;;
        *) die "usage: droid watch start|stop|status" ;;
      esac ;;
    __watch) watch_loop ;;
    setup|doctor)
      printf '%-16s %s\n' 'rish' "$RISH"
      printf '%-16s %s\n' 'terminal pkg' "$TERM_PKG"
      if jar="$(helper_jar)"; then
        printf '%-16s %s\n' 'notify helper' "$jar"
      else
        printf '%-16s %s\n' 'notify helper' \
          "MISSING - run $SCRIPT_DIR/build-helper.sh (pkg install openjdk-21 d8)"
      fi
      case ":$PATH:" in
        *":$HOME/bin:"*) printf '%-16s %s\n' 'PATH' "$HOME/bin present" ;;
        *) printf '%-16s %s\n' 'PATH' "add \$HOME/bin to PATH" ;;
      esac
      printf '%-16s ' 'shell check'
      if run 'id' 2>/dev/null | grep -q 'uid=2000'; then
        echo 'ok (shell uid 2000)'
      else
        echo 'FAILED - run: droid wake'
      fi ;;
    *) die "unknown command: $cmd (try: droid help)" ;;
  esac
}

main "$@"
