#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Battery
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Says the battery level and whether it's charging.
# @echo.phrases battery level, battery percentage, how much battery, hows my battery, whats my battery, how much battery do i have

info=$(pmset -g batt)
percent=$(echo "$info" | grep -Eo '[0-9]+%' | head -1)
if [ -z "$percent" ]; then echo "This Mac has no battery."; exit 0; fi
state=$(echo "$info" | grep -Eo '(discharging|charging|charged|finishing charge|AC attached)' | head -1)
case "$state" in
  charging|"finishing charge") line="Battery is at $percent and charging." ;;
  charged) line="Battery is at $percent and fully charged." ;;
  "AC attached") line="Battery is at $percent, plugged in but not charging." ;;
  *)
    left=$(echo "$info" | grep -Eo '[0-9]+:[0-9]+ remaining' | head -1 | cut -d' ' -f1)
    hours=${left%%:*}; minutes=${left#*:}; minutes=$((10#${minutes:-0}))
    if [ -z "$left" ] || [ "$left" = "0:00" ]; then line="Battery is at $percent."
    elif [ "$hours" -eq 1 ]; then line="Battery is at $percent, about 1 hour $minutes minutes left."
    elif [ "$hours" -gt 1 ]; then line="Battery is at $percent, about $hours hours $minutes minutes left."
    else line="Battery is at $percent, about $minutes minutes left."; fi ;;
esac
echo "$line"
