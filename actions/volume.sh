#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Volume
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Sets the volume: a number from 0 to 100, or up or down.
# @raycast.argument1 { "type": "text", "placeholder": "0 to 100, up or down" }
# @echo.phrases set volume to, set the volume to, volume to, turn the volume to

current=$(osascript -e 'output volume of (get volume settings)')
case "$1" in
  *up*|*louder*) level=$((current + 15)) ;;
  *down*|*quieter*|*lower*) level=$((current - 15)) ;;
  *) level=$(echo "$1" | tr -cd '0-9') ;;
esac
if [ -z "$level" ]; then echo "Say a number, like volume 30."; exit 1; fi
[ "$level" -gt 100 ] && level=100
[ "$level" -lt 0 ] && level=0
osascript -e "set volume output volume $level without output muted" || exit 1
echo "Volume $level."
