#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Open Last Download
# @raycast.mode silent
# @raycast.packageName Echo One
# @raycast.description Opens the newest file in Downloads.
# @echo.phrases open my last download, open the last download, open latest download, open my latest download

newest=$(ls -t "$HOME/Downloads" | grep -v '^\.' | head -1)
if [ -z "$newest" ]; then echo "Downloads is empty."; exit 0; fi
open "$HOME/Downloads/$newest" || exit 1
name=${newest%.*}
[ ${#name} -gt 40 ] && name="${name:0:40}…"
echo "Opened $name."
