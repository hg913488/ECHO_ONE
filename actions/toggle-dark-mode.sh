#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Toggle Dark Mode
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Switches between dark and light mode.
# @echo.phrases switch appearance, toggle appearance

dark=$(osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
tell application "System Events" to tell appearance preferences to get dark mode') || exit 1
[ "$dark" = "true" ] && echo "Dark mode is on." || echo "Light mode is on."
