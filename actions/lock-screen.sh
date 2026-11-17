#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Lock Screen
# @raycast.mode silent
# @raycast.packageName Echo One
# @raycast.description Locks the Mac, like pressing Control-Command-Q.
# @echo.phrases lock the screen, lock my screen, lock the mac, lock my mac, lock computer

osascript -e 'tell application "System Events" to keystroke "q" using {control down, command down}' || exit 1
echo "Locked."
