#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Light Mode
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Switches the Mac to light mode.
# @echo.phrases turn on light mode, light mode on, switch to light mode, turn off dark mode, dark mode off

osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' >/dev/null || exit 1
echo "Light mode is on."
