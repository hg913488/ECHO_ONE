#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Hide Hidden Files
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Hides hidden files in Finder again.
# @echo.phrases hide hidden files in finder

defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder || exit 1
echo "Hidden files are hidden."
