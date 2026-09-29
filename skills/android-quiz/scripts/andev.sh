#!/usr/bin/env bash
# andev - one transport for driving an Android screen, plus pixel-based helpers.
#
# Supports three ways to reach the target device, chosen automatically (see
# `andev detect`):
#   adb  - USB / wireless debugging / emulator (works from any OS with platform-tools)
#   rish - on-device Shizuku shell (uid 2000), when running inside Termux
#   su   - on-device root
#
# Needs bash. Either run it (`bash scripts/andev.sh detect`) or source it from
# bash (`. scripts/andev.sh`). Sourcing from dash/sh will not work.
#
# Everything is deliberately transport-agnostic: "what to do" is the action
# string, "how to touch the device" is the transport. Swap transports without
# changing the actions (the same lesson as MaaFramework resource/controller
# separation).

if [ -z "${BASH_VERSION:-}" ]; then
  echo "andev: bash is required - run 'bash $0 detect', or source it from bash" >&2
  return 1 2>/dev/null || exit 1
fi

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PXJS="$SELF_DIR/px.js"
DUMPJS="$SELF_DIR/dump.js"
RAW="${RAW:-${TMPDIR:-/tmp}/andev-frame.raw}"
ANDROID_SERIAL="${ANDROID_SERIAL:-}"
TRANSPORT="${TRANSPORT:-}"
PKG="${PKG:-}"

say()  { printf '%s\n' "$*"; }
warn() { printf 'andev: %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

# ---------------------------------------------------------------- adb plumbing
# Some launchers point LD_LIBRARY_PATH at bundled libs that break adb's linking.
andev_adb() { env -u LD_LIBRARY_PATH -u LD_PRELOAD adb ${ANDROID_SERIAL:+-s "$ANDROID_SERIAL"} "$@"; }
has_adb()   { command -v adb >/dev/null 2>&1 && andev_adb version >/dev/null 2>&1; }

adb_first_device() {
  andev_adb devices 2>/dev/null | awk 'NR>1 && $2=="device" { print $1; exit }'
}

# ------------------------------------------------------------------- detection
_dev_sh_adb()  { andev_adb shell "$1"; }
_dev_sh_rish() { "$RISH" -c "$1"; }
_dev_sh_su()   { su -c "$1"; }

dev_sh() {
  case "$TRANSPORT" in
    adb)  _dev_sh_adb "$1" ;;
    rish) _dev_sh_rish "$1" ;;
    su)   _dev_sh_su "$1" ;;
    *)    die "no transport selected; run: andev detect" ;;
  esac
}

andev_detect() {
  local adb_bin="" dev="" on_android="no" rish_ok="no" su_ok="no"
  say "== environment =="
  [ -n "${PREFIX:-}" ] && say "termux prefix     $PREFIX"
  case "$(uname -o 2>/dev/null)" in Android*) on_android="yes" ;; esac
  say "host              $(uname -srm) (android=$on_android)"

  if command -v adb >/dev/null 2>&1; then
    adb_bin="$(command -v adb)"
    if andev_adb version >/dev/null 2>&1; then
      say "adb               $adb_bin ($(andev_adb version | head -1))"
      dev="$(adb_first_device)"
      if [ -n "$dev" ]; then
        say "adb device        $dev"
        ANDROID_SERIAL="${ANDROID_SERIAL:-$dev}"
      else
        say "adb device        (none attached)"
      fi
    else
      say "adb               $adb_bin (present but not runnable)"
    fi
  else
    say "adb               not found"
  fi

  if [ "$on_android" = "yes" ]; then
    local r="${RISH:-$HOME/rish}"
    [ -f "$HOME/rish" ] && r="$HOME/rish"
    RISH="$r"
    if [ -x "$r" ] && RISH_APPLICATION_ID="${RISH_APPLICATION_ID:-com.termux}" "$r" -c 'id' 2>/dev/null |
         grep -q 'uid=2000'; then
      rish_ok="yes"
      say "rish (shizuku)    ok -> $r  (shell uid 2000)"
    else
      say "rish (shizuku)    not usable (open the Shizuku app once, then retry)"
    fi
    if su -c 'id' 2>/dev/null | grep -q 'uid=0'; then
      su_ok="yes"; say "root (su)         ok"
    else
      say "root (su)         not available"
    fi
  fi

  # pick a transport: an attached adb device wins, then on-device shizuku, then root
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    TRANSPORT=adb
  elif [ "$rish_ok" = "yes" ]; then
    TRANSPORT=rish
  elif [ "$su_ok" = "yes" ]; then
    TRANSPORT=su
  else
    TRANSPORT=""
  fi
  say "transport         ${TRANSPORT:-NONE}"

  if [ -n "$TRANSPORT" ]; then
    local id model brand qemu chars type rel api
    id="$(dev_sh 'id' 2>/dev/null | head -1)"
    model="$(dev_sh 'getprop ro.product.model' 2>/dev/null)"
    brand="$(dev_sh 'getprop ro.product.brand' 2>/dev/null)"
    qemu="$(dev_sh 'getprop ro.kernel.qemu' 2>/dev/null)"
    chars="$(dev_sh 'getprop ro.build.characteristics' 2>/dev/null)"
    type="physical"
    case "$ANDROID_SERIAL" in emulator-*) type="emulator" ;; esac
    case "$qemu$chars" in *1*|*emulator*) type="emulator" ;; esac
    say "target kind       $type  ($brand $model)"
    say "shell identity    ${id:-unknown}"
    rel="$(dev_sh 'getprop ro.build.version.release' 2>/dev/null)"
    api="$(dev_sh 'getprop ro.build.version.sdk' 2>/dev/null)"
    say "android           ${rel:-?} (API ${api:-?})"
    say "screen            $(dev_sh 'wm size' 2>/dev/null | head -1)"
    say "root              $(dev_sh 'su -c id' 2>/dev/null | grep -q 'uid=0' && echo yes || echo no)"
  fi
}

# --------------------------------------------------------------- device actions
_touch() { # x y [ms]
  if [ -n "${3:-}" ]; then
    dev_sh "input swipe $1 $2 $1 $2 $3"
  else
    dev_sh "input tap $1 $2"
  fi
}
dev_tap()   { _touch "$1" "$2" "${3:-120}"; }   # 120 ms press: still a tap, dot visible
dev_swipe() { dev_sh "input swipe $1 $2 $3 $4 ${5:-300}"; }
dev_key()   { dev_sh "input keyevent $1"; }
dev_text()  { dev_sh "input text '$1'"; }
dev_fg()    { dev_sh 'dumpsys window 2>/dev/null | grep -m1 mCurrentFocus' 2>&1; }
dev_pkg()   { dev_fg | sed -E 's/.*u0 ([^\/ ]+).*/\1/'; }
dev_app()   { dev_sh "monkey -p $1 -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1; sleep 3; }

dev_shot_raw() { # [local_path]
  local out="${1:-$RAW}"
  case "$TRANSPORT" in
    adb)  andev_adb exec-out screencap > "$out" ;;
    rish) "$RISH" -c 'screencap > /sdcard/.andev.raw'; cp /sdcard/.andev.raw "$out"
          "$RISH" -c 'rm -f /sdcard/.andev.raw' >/dev/null 2>&1 ;;
    su)   su -c 'screencap > /data/local/tmp/.andev.raw'
          su -c 'cat /data/local/tmp/.andev.raw' > "$out"
          su -c 'rm -f /data/local/tmp/.andev.raw' ;;
  esac
}
dev_shot_png() { # [local_path]
  local out="${1:-${RAW%.raw}.png}"
  case "$TRANSPORT" in
    adb)  andev_adb exec-out screencap -p > "$out" ;;
    rish) "$RISH" -c 'screencap -p /sdcard/.andev.png'; cp /sdcard/.andev.png "$out"
          "$RISH" -c 'rm -f /sdcard/.andev.png' >/dev/null 2>&1 ;;
    su)   su -c 'screencap -p /data/local/tmp/.andev.png'
          su -c 'cat /data/local/tmp/.andev.png' > "$out" ;;
  esac
  printf '%s\n' "$out"
}

# ------------------------------------------------------------------- pixel tools
px_probe()  { RAW="$RAW" node "$PXJS" probe "$@"; }
px_sel()    { RAW="$RAW" node "$PXJS" sel "$@"; }
px_find()   { RAW="$RAW" node "$PXJS" find "$@"; }
px_blocks() { RAW="$RAW" node "$PXJS" blocks "$@"; }
px_size()   { RAW="$RAW" node "$PXJS" size; }
px_learn_rows() { RAW="$RAW" node "$PXJS" learn-rows "$@"; }
px_check_rows() { RAW="$RAW" node "$PXJS" check-rows "$@"; }
px_locate_row() { RAW="$RAW" node "$PXJS" locate-row "$@"; }
px_sweep()      { node "$PXJS" sweep "$@"; }
px_selected()   { node "$PXJS" selected "$@"; }

# ------------------------------------------------------------- text-first path
# One uiautomator dump yields the stem, every option and every button with real
# bounds - far cheaper than looking at a screenshot. Parse it locally.
DEV_DUMP_DIR="${DEV_DUMP_DIR:-/sdcard/.andev-dumps}"

dev_dump() {   # [local xml path]
  local out="${1:-$HOME/.andev-dump.xml}"
  dev_sh 'uiautomator dump /sdcard/.andev-dump.xml' >/dev/null 2>&1
  case "$TRANSPORT" in
    adb)  andev_adb pull /sdcard/.andev-dump.xml "$out" >/dev/null 2>&1 ;;
    *)    cp /sdcard/.andev-dump.xml "$out" 2>/dev/null ;;
  esac
  [ -s "$out" ] || { warn "uiautomator dump produced nothing"; return 1; }
  printf '%s\n' "$out"
}

# dev_collect <maxQuestions> [nextLabel] [sleepSecs] [localDir]
# Walks a quiz set in ONE round trip: dump -> find the "next" button's real
# bounds -> tap its centre -> repeat. Prints the local directory of XML files.
dev_collect() {
  local n="${1:-50}" label="${2:-下一题}" slp="${3:-1.1}" out="${4:-$HOME/.andev-dumps}"
  local stage=/sdcard/.andev-collect.sh dir="$DEV_DUMP_DIR"
  printf '%s\n' \
    "rm -rf $dir; mkdir -p $dir" \
    'i=0' \
    "while [ \$i -lt $n ]; do" \
    '  i=$((i+1))' \
    "  uiautomator dump $dir/d\$i.xml >/dev/null 2>&1" \
    "  [ -s $dir/d\$i.xml ] || break" \
    "  b=\$(grep -o 'text=\"$label\"[^>]*bounds=\"\\[[0-9]*,[0-9]*\\]\\[[0-9]*,[0-9]*\\]\"' $dir/d\$i.xml | tail -1 | sed 's/.*\\[\\([0-9]*\\),\\([0-9]*\\)\\]\\[\\([0-9]*\\),\\([0-9]*\\)\\].*/\\1 \\2 \\3 \\4/')" \
    '  [ -n "$b" ] || break' \
    '  set -- $b' \
    '  input tap $(( ($1+$3)/2 )) $(( ($2+$4)/2 ))' \
    "  sleep $slp" \
    'done' \
    "ls $dir/*.xml 2>/dev/null | wc -l" > "$stage"
  dev_sh "sh $stage"
  mkdir -p "$out"
  case "$TRANSPORT" in
    adb)  andev_adb pull "$dir/." "$out/" >/dev/null 2>&1 ;;
    *)    cp "$dir"/*.xml "$out"/ 2>/dev/null ;;
  esac
  printf '%s\n' "$out"
}

dump_nodes() { node "$DUMPJS" nodes "$@"; }
dump_find()  { node "$DUMPJS" find "$@"; }
dump_any()   { node "$DUMPJS" any "$@"; }
dump_quiz()  { node "$DUMPJS" quiz "$@"; }

# ------------------------------------------------------- one-trip capture set
# Capture one frame per question in a SINGLE round trip, then locate every
# question's option row locally. This is what removes the 30-60 round trips a
# naive run spends on look-tap-look-tap.
DEV_SHOT_DIR="${DEV_SHOT_DIR:-/sdcard/.andev-shots}"

dev_capture() {   # <tabY> <tabX...>   -> prints the local directory of frames
  local tabY="$1"; shift
  local out="${2:-$HOME/.andev-shots}"
  local i=0 script="rm -rf $DEV_SHOT_DIR; mkdir -p $DEV_SHOT_DIR;"
  for x in "$@"; do
    i=$((i + 1))
    script="$script input swipe $x $tabY $x $tabY 120; sleep 1.4; screencap > $DEV_SHOT_DIR/q$i.raw;"
  done
  dev_sh "$script" >/dev/null 2>&1 || { warn "capture failed"; return 1; }
  mkdir -p "$out"
  case "$TRANSPORT" in
    adb)  andev_adb pull "$DEV_SHOT_DIR/." "$out/" >/dev/null 2>&1 ;;
    *)    cp "$DEV_SHOT_DIR"/*.raw "$out"/ 2>/dev/null ;;
  esac
  printf '%s\n' "$out"
}

dev_locate_row() { # <profile.json> <name> <y0,y1> [step]  (fresh frame + locate)
  local profile="$1"; shift
  dev_shot_raw
  px_locate_row "$profile" "$@"
}

# ---------------------------------------------------------------- layout cache
# Learn the fixed rows (option boxes, question numbers) ONCE per app+screen,
# then only re-check them - a single-row scan instead of a full-image search.
dev_learn_layout() {   # <profile.json> <y:name> [y:name ...]
  local profile="$1"; shift
  dev_shot_raw
  px_learn_rows "$profile" "$@"
}
dev_check_layout() {   # <profile.json> [tolPx]   (rewrites centres, exits !=0 if changed)
  local profile="$1"; shift
  dev_shot_raw
  px_check_rows "$profile" "$@"
}
# Tap a remembered element: <profile> <row> <A|B|...|1|2|...>
dev_tap_el() {
  local pt
  pt="$(node -e '
const fs=require("fs");
const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
const row=p.rows[process.argv[2]];
if(!row){console.error("no such row: "+process.argv[2]);process.exit(1);}
let i=Number(process.argv[3]);
if(Number.isNaN(i)) i=process.argv[3].toUpperCase().charCodeAt(0)-64;
const r=row.runs[i-1];
if(!r){console.error("no such element: "+process.argv[3]);process.exit(1);}
console.log(r.cx+","+row.y);
' "$1" "$2" "$3")" || return 1
  dev_tap "${pt%,*}" "${pt#*,}"
}

# --------------------------------------------------------------- guarded batch
# dev_batch <pkg> <actions>
#   ONE transport round trip for: foreground guard + all actions + a raw frame.
#   Refuses to act when another app owns the focused window, so a mistimed tap
#   can never land in whatever the user is looking at.
# dev_seq is the same but re-launches the app and retries once.
dev_batch() {
  local pkg="$1" actions="$2" fg tries=0
  # The guard used to fire on an EMPTY focus read (transport hiccup) and then
  # relaunch the app, which loses the quiz position. Retry the read first.
  while :; do
    fg="$(dev_fg)"
    [ -n "$fg" ] && break
    tries=$((tries + 1))
    if [ "$tries" -ge 3 ]; then
      warn "cannot read the focused window (empty output); aborting instead of relaunching"
      return 1
    fi
    sleep 1
  done
  case "$fg" in
    *"$pkg"*) ;;
    *) warn "refusing: focused window is not $pkg -> $fg"; return 1 ;;
  esac
  dev_sh "$actions"
  dev_shot_raw
}
dev_seq() {
  dev_batch "$1" "$2" && return 0
  dev_app "$1"
  dev_batch "$1" "$2"
}

# ---------------------------------------------------------------- device memory
# First time on a device: detect, calibrate, remember. Every later run on the
# same device reads the memory and skips detection entirely.
ANDROID_QUIZ_HOME="${ANDROID_QUIZ_HOME:-$HOME/.android-quiz}"

ensure_transport() {
  [ -n "$TRANSPORT" ] && return 0
  andev_detect >/dev/null 2>&1
  [ -n "$TRANSPORT" ] || { warn "no usable transport (run: andev detect)"; return 1; }
}

# Device facts in ONE round trip, retried until every field is non-empty.
# `rish` output occasionally arrives late, so a multi-call read can silently
# capture an empty field - which is exactly what made the device key unstable
# (and what the field notes recorded as "the guard got an empty focus").
dev_facts() {
  ensure_transport || return 1
  local out tries=0
  while :; do
    out="$(dev_sh 'b=$(getprop ro.product.brand); m=$(getprop ro.product.model);
s=$(getprop ro.build.version.sdk); f=$(getprop ro.build.fingerprint);
r=$(getprop ro.build.version.release); i=$(getprop ro.build.version.incremental);
z=$(wm size | head -1 | tr -dc 0-9x); d=$(wm density | head -1 | tr -dc 0-9);
echo "$b|$m|$s|$f|$r|$i|$z|$d"' 2>&1)"
    # every field must be present, otherwise the read raced
    if [ "$(printf '%s' "$out" | awk -F'|' 'NF==8 && $1!="" && $2!="" && $3!="" && $4!="" && $7!="" && $8!="" {print "ok"}')" = "ok" ]; then
      printf '%s' "$out"
      return 0
    fi
    tries=$((tries + 1))
    [ "$tries" -ge 5 ] && { warn "could not read stable device facts"; printf '%s' "$out"; return 1; }
    sleep 0.4
  done
}

# A stable, non-secret device fingerprint: same phone -> same key -> same memory.
dev_key() {
  local facts
  facts="$(dev_facts)" || return 1
  printf '%s' "$facts" | cksum | awk '{printf "dev-%s", $1}'
}

dev_fact_field() {  # <1..8>
  dev_facts | cut -d'|' -f"$1"
}

dev_memory_file() { printf '%s/devices/%s.json' "$ANDROID_QUIZ_HOME" "$(dev_key)"; }

andev_profile() {
  ensure_transport || return 1
  local file
  file="$(dev_memory_file)"
  printf 'device key   %s\n' "$(dev_key)"
  printf 'memory       %s\n' "$file"
  if [ -f "$file" ]; then
    printf 'status       KNOWN device - reuse this, do NOT re-detect\n'
    node -e '
      const p = require(process.argv[1]);
      const d = p.device || {};
      console.log("calibrated   " + (p.calibrated_at || "?") + " via " + (p.transport || "?"));
      console.log("device       " + [d.brand, d.model, d.size, (d.density ? d.density + "dpi" : ""), ("API " + (d.sdk || "?"))].filter(Boolean).join(" "));
      const apps = Object.keys(p.apps || {});
      console.log("apps         " + (apps.join(", ") || "(none remembered yet)"));
      for (const a of apps) console.log("  " + a + "  " + JSON.stringify(p.apps[a]));
    ' "$file"
  else
    printf 'status       FIRST RUN on this device\n'
    printf 'next         andev calibrate <optionY>:options <tabY>:qtabs\n'
    printf '             then: andev remember <pkg> rows="{\\"options\\":Y}" selected_rgb="[..]" ...\n'
  fi
}

andev_calibrate() {   # [y:name ...]  -> detect, optionally learn rows, remember
  ensure_transport || return 1
  local file dir size brand model rel sdk dens rom facts
  file="$(dev_memory_file)"; dir="$(dirname "$file")"
  mkdir -p "$dir"
  dev_shot_raw || return 1
  size="$(px_size)"
  facts="$(dev_facts)" || return 1
  brand="$(printf '%s' "$facts" | cut -d'|' -f1)"
  model="$(printf '%s' "$facts" | cut -d'|' -f2)"
  sdk="$(printf '%s' "$facts" | cut -d'|' -f3)"
  rel="$(printf '%s' "$facts" | cut -d'|' -f5)"
  rom="$(printf '%s' "$facts" | cut -d'|' -f6)"
  dens="$(printf '%s' "$facts" | cut -d'|' -f8)"
  if [ $# -gt 0 ]; then
    px_learn_rows "$ANDROID_QUIZ_HOME/layout-$size.json" "$@" >/dev/null || return 1
    printf 'learned rows -> %s\n' "$ANDROID_QUIZ_HOME/layout-$size.json"
  fi
  printf '%s\n' \
    '{' \
    "  \"calibrated_at\": \"$(date -Iseconds 2>/dev/null || date)\"," \
    "  \"transport\": \"$TRANSPORT\"," \
    '  "device": {' \
    "    \"brand\": \"$brand\", \"model\": \"$model\", \"release\": \"$rel\"," \
    "    \"sdk\": \"$sdk\", \"size\": \"$size\", \"density\": \"$dens\", \"rom\": \"$rom\"" \
    '  },' \
    '  "apps": {}' \
    '}' > "$file"
  printf 'remembered   %s\n' "$file"
  printf 'device       %s %s %s @%sdpi API %s\n' "$brand" "$model" "$size" "$dens" "$sdk"
}

# andev remember <pkg> key=value [key=value ...]
# Record what you learned about an app on this device (rows, colours, layout
# profile path, dialog positions ...) so the next run can skip re-discovery.
andev_remember() {
  local pkg="${1:-}" kv file
  shift 2>/dev/null || true
  [ -n "$pkg" ] || { warn "usage: andev remember <pkg> key=value ..."; return 2; }
  file="$(dev_memory_file)"
  [ -f "$file" ] || andev_calibrate >/dev/null || return 1
  node -e '
    const fs = require("fs");
    const [, file, pkg, ...kvs] = process.argv;
    const p = JSON.parse(fs.readFileSync(file, "utf8"));
    p.apps = p.apps || {};
    p.apps[pkg] = p.apps[pkg] || {};
    for (const kv of kvs) {
      const i = kv.indexOf("=");
      if (i < 0) continue;
      const k = kv.slice(0, i);
      let v = kv.slice(i + 1);
      try { v = JSON.parse(v); } catch (e) { /* keep as string */ }
      p.apps[pkg][k] = v;
    }
    p.apps[pkg].updated_at = new Date().toISOString();
    fs.writeFileSync(file, JSON.stringify(p, null, 2) + "\n");
    console.log("remembered " + pkg + ": " + JSON.stringify(p.apps[pkg]));
  ' "$file" "$pkg" "$@"
}

andev_recall() {   # <pkg>
  local pkg="${1:-}" file
  [ -n "$pkg" ] || { warn "usage: andev recall <package>"; return 2; }
  file="$(dev_memory_file)"
  [ -f "$file" ] || { printf 'FIRST RUN: nothing remembered on this device yet\n'; return 1; }
  node -e '
    const p = require(process.argv[1]);
    const a = (p.apps || {})[process.argv[2]];
    if (!a) { console.log("no memory for " + process.argv[2] + " on this device"); process.exit(1); }
    console.log(JSON.stringify(a, null, 2));
    console.log("device: " + JSON.stringify(p.device));
  ' "$file" "$pkg"
}

andev() {
  case "${1:-}" in
    detect|"") andev_detect ;;
    profile) andev_profile ;;
    calibrate) shift; andev_calibrate "$@" ;;
    recall) shift; andev_recall "$@" ;;
    remember) shift; andev_remember "$@" ;;
    -h|--help)
      cat <<'EOF'
andev - Android UI automation transport (adb / rish / su) + pixel helpers

  andev detect                 probe the environment and pick a transport
  andev profile                device memory: known device, or FIRST RUN?
  andev calibrate [y:name...]  detect + learn rows + remember this device
  andev remember <pkg> k=v...  record app facts (rows, colours, dialogs) for next time
  andev recall <pkg>           print what was remembered for a package
  dev_sh '<cmd>'               run a shell command on the device
  dev_tap X Y [ms]             tap (120 ms press by default)
  dev_swipe X1 Y1 X2 Y2 [ms]
  dev_key KEYCODE | dev_text 'STR'
  dev_fg | dev_pkg             focused window / package
  dev_app <pkg>                launch a package
  dev_shot_raw [file]          raw RGBA frame (readable by px.js)
  dev_shot_png [file]          PNG frame (for a human or a vision model)
  dev_batch <pkg> '<actions>'  guarded: foreground check + actions + frame
  dev_seq   <pkg> '<actions>'  same, but relaunch the app and retry once
  px_size | px_probe x,y... | px_sel x,y... | px_find mode x0,y0,x1,y1 | px_blocks r,g,b
  dev_learn_layout <profile.json> <y:name>...   learn the fixed rows ONCE
  dev_check_layout <profile.json> [tolPx]       re-check rows cheaply (rewrites centres)
  dev_tap_el <profile.json> <row> <A|B|1|2>     tap a remembered element
  dev_capture <tabY> <tabX...>                  one round trip -> frames for all questions
  px_sweep <profile.json> <row> <y0,y1> <dir>   locate the row in every captured frame
  px_selected <profile.json> <row> <dir> [y0,y1]  which option is selected, per frame
  dev_dump [out.xml]                            one a11y dump + parse locally
  dump_nodes <file.xml> | dump_find <file.xml> <text> | dump_quiz <file.xml>
  dev_collect <maxQ> ["下一题"] [sleep] [dir]    walk the whole set in ONE round trip

Text first: a uiautomator dump gives the stem, the option labels and the real
bounds of every button in a single call - use it instead of reading screenshots,
and use pixels only to confirm a tap. Hybrid WebViews keep the previous page in
the tree, so anchor on the LAST 【第N题】 and cut at 上一题/下一题/交卷.
  dev_locate_row <profile.json> <row> <y0,y1>   find the row inside a band on the live screen

Layout cache: option boxes and question numbers do not move between questions, so
learn them once per app+screen and then reuse the coordinates. Only re-learn when
dev_check_layout reports CHANGED (different device, app update, theme change).

Rows that DO move (the option row shifts with the length of the question stem):
learn the row shape once, then find it inside a y-band with dev_locate_row /
px_sweep instead of trusting the remembered y.
EOF
      ;;
    *) warn "unknown command: $1 (try: andev --help)"; return 2 ;;
  esac
}

# Run directly (not sourced) as a script too.
if [ "${BASH_SOURCE[0]:-}" = "$0" ]; then
  andev "$@"
fi
