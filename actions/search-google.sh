#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Search Google
# @raycast.mode silent
# @raycast.packageName Echo One
# @raycast.description Opens a Google search in your browser.
# @raycast.argument1 { "type": "text", "placeholder": "search" }
# @echo.phrases google, search google for, search the web for, google search

query=$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "$1") || exit 1
open "https://www.google.com/search?q=$query" || exit 1
echo "Searching Google."
