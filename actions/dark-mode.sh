#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Dark Mode
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Switches the Mac to dark mode.
# @echo.phrases turn on dark mode, dark mode on, switch to dark mode, go dark

osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null || exit 1
echo "Dark mode is on."
