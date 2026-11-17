#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Quit All Apps
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Quits every open app except Finder and Echo One. Apps with unsaved work will ask first.
# @raycast.needsConfirmation true
# @echo.phrases quit everything, close all apps, quit all my apps, close everything

count=$(osascript <<'APPLESCRIPT'
tell application "System Events" to set appNames to name of every application process whose background only is false
set quitCount to 0
repeat with appName in appNames
  set appName to appName as text
  if appName is not in {"Finder", "EchoOne", "Echo One"} then
    try
      tell application appName to quit
      set quitCount to quitCount + 1
    end try
  end if
end repeat
return quitCount
APPLESCRIPT
) || exit 1
[ "$count" -eq 1 ] && echo "Quit 1 app." || echo "Quit $count apps."
