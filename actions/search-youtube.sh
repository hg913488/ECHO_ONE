#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Search YouTube
# @raycast.mode silent
# @raycast.packageName Echo One
# @raycast.description Opens a YouTube search in your browser.
# @raycast.argument1 { "type": "text", "placeholder": "search" }
# @echo.phrases youtube, search youtube for, find on youtube

query=$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "$1") || exit 1
open "https://www.youtube.com/results?search_query=$query" || exit 1
echo "Searching YouTube."
