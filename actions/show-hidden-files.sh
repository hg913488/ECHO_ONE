#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Show Hidden Files
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Shows hidden files in Finder.
# @echo.phrases show hidden files in finder

defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder || exit 1
echo "Hidden files are showing."
