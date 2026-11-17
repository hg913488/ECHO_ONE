#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Quit App
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Quits an app by name.
# @raycast.argument1 { "type": "text", "placeholder": "app name" }
# @echo.phrases quit, close app, close the app

name=$(echo "$1" | tr -d '"\\')
if ! running=$(osascript -e "application \"$name\" is running" 2>/dev/null); then
  echo "I couldn't find an app called $name."
  exit 1
fi
if [ "$running" != "true" ]; then echo "$name isn't open."; exit 0; fi
osascript -e "tell application \"$name\" to quit" || exit 1
echo "Quit $name."
