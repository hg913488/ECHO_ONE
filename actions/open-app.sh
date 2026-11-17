#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Open App
# @raycast.mode silent
# @raycast.packageName Echo One
# @raycast.description Opens an app by name. Anything that isn't an app goes to the Voice Agent instead.
# @raycast.argument1 { "type": "text", "placeholder": "app name" }
# @echo.phrases open, launch

name="$1"
# Exit 75 tells Echo One "not mine": the command goes to the Voice Agent instead.
open -Ra "$name" 2>/dev/null || exit 75
open -a "$name" || exit 1
echo "Opening $name."
