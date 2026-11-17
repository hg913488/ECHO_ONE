#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Show Desktop Icons
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Shows the desktop icons again.
# @echo.phrases show my desktop icons, show desktop, show my desktop

defaults write com.apple.finder CreateDesktop -bool true && killall Finder || exit 1
echo "Desktop icons are back."
