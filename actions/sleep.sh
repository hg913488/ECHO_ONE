#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Sleep
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Puts the Mac to sleep after a short pause.
# @raycast.needsConfirmation true
# @echo.phrases put the mac to sleep, go to sleep, sleep the mac, sleep now

# The pause lets Echo One finish speaking first.
(sleep 3; pmset sleepnow) >/dev/null 2>&1 &
echo "Going to sleep."
