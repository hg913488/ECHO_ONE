#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Unmute
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Turns the sound back on.
# @echo.phrases unmute the sound, unmute sound, unmute the mac, sound on

osascript -e 'set volume without output muted' || exit 1
echo "Sound is on."
