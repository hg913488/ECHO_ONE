#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Keep Awake
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Keeps the Mac and its display awake until you say stop keeping awake.
# @echo.phrases keep the mac awake, keep my mac awake, stay awake, dont sleep, caffeinate

pidfile="${TMPDIR:-/tmp}/echo-one-keep-awake.pid"
if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
  echo "Already keeping the Mac awake."
  exit 0
fi
nohup caffeinate -di >/dev/null 2>&1 &
echo $! > "$pidfile"
echo "Keeping the Mac awake."
