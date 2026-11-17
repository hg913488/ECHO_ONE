#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Empty Trash
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Empties the Trash. This can't be undone, so Echo One asks first.
# @raycast.needsConfirmation true
# @echo.phrases empty the trash, empty my trash, empty the bin

count=$(osascript -e 'tell application "Finder" to count items of trash') || exit 1
if [ "$count" -eq 0 ]; then echo "The Trash is already empty."; exit 0; fi
osascript -e 'tell application "Finder" to empty trash' >/dev/null || exit 1
[ "$count" -eq 1 ] && echo "Emptied the Trash, 1 item." || echo "Emptied the Trash, $count items."
