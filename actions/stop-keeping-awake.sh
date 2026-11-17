#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Stop Keeping Awake
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Lets the Mac sleep normally again.
# @echo.phrases let the mac sleep, allow sleep, stop caffeinate, stop staying awake

pidfile="${TMPDIR:-/tmp}/echo-one-keep-awake.pid"
if [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; then
  : > "$pidfile"
  echo "The Mac can sleep again."
else
  echo "The Mac wasn't being kept awake."
fi
