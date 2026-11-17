#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Open Desktop
# @raycast.mode silent
# @raycast.packageName Echo One
# @raycast.description Opens your Desktop folder in Finder.
# @echo.phrases open my desktop, open the desktop folder, open my desktop folder, show my desktop

open "$HOME/Desktop" || exit 1
echo "Opened Desktop."
