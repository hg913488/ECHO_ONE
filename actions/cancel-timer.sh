#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Cancel Timer
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Cancels the timer.
# @echo.phrases stop the timer, cancel the timer, stop timer, cancel my timer

pidfile="${TMPDIR:-/tmp}/echo-one-timer.pid"
pid=$(cat "$pidfile" 2>/dev/null)
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
  waiting=$(pgrep -P "$pid")
  kill "$pid" $waiting 2>/dev/null
  : > "$pidfile"
  echo "Timer cancelled."
else
  echo "There's no timer running."
fi
