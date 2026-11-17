#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Mute
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Mutes the sound.
# @echo.phrases mute the sound, mute sound, mute the mac, mute volume

osascript -e 'set volume with output muted' || exit 1
echo "Muted."
