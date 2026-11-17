#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Copy Last Screenshot
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Copies your newest screenshot to the clipboard, ready to paste.
# @echo.phrases copy my last screenshot, copy the last screenshot, copy latest screenshot, copy my latest screenshot

folder=$(defaults read com.apple.screencapture location 2>/dev/null)
folder=${folder/#\~/$HOME}
[ -d "$folder" ] || folder="$HOME/Desktop"
# Spotlight knows which images are screenshots even after they're renamed.
newest=$(mdfind -onlyin "$folder" 'kMDItemIsScreenCapture == 1' -0 | xargs -0 ls -t 2>/dev/null | head -1)
[ -z "$newest" ] && newest=$(ls -t "$folder"/*.png 2>/dev/null | head -1)
if [ -z "$newest" ]; then echo "I couldn't find a screenshot."; exit 1; fi
case "$newest" in
  *.jpg|*.jpeg|*.JPG|*.JPEG) kind="JPEG" ;;
  *) kind="PNGf" ;;
esac
osascript -e "set the clipboard to (read (POSIX file \"$newest\") as «class $kind»)" || exit 1
echo "Copied your last screenshot."
