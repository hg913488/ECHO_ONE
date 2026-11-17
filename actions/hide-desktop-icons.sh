#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Hide Desktop Icons
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Hides everything on the desktop, handy before a screen recording.
# @echo.phrases hide my desktop icons, hide desktop, hide my desktop, clean desktop

defaults write com.apple.finder CreateDesktop -bool false && killall Finder || exit 1
echo "Desktop icons are hidden."
