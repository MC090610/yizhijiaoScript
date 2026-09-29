#!/usr/bin/env bash
# Build the droid-notify helper: Java -> dex ("apk") that app_process can load.
#
#   pkg install openjdk-21 d8
#   scripts/build-helper.sh
#
# Output: scripts/termux_notify/droid-notify.jar (a zip holding classes.dex;
# chmod 0400 - Android 14+
# refuses to load a writable dex).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="$HERE/termux_notify"
SRC="$DIR/DroidNotify.java"
OUT="$DIR/droid-notify.jar"

command -v javac >/dev/null 2>&1 || { echo "missing javac: pkg install openjdk-21" >&2; exit 1; }
command -v d8 >/dev/null 2>&1 || { echo "missing d8: pkg install d8" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

javac --release 8 -nowarn -d "$WORK" "$SRC" 2>&1 | grep -v -E 'bootstrap class path|deprecat' || true
[ -f "$WORK/DroidNotify.class" ] || { echo "javac failed" >&2; exit 1; }

rm -f "$OUT"
d8 --min-api 26 --output "$OUT" "$WORK/DroidNotify.class"
chmod 0400 "$OUT"
ls -l "$OUT"
