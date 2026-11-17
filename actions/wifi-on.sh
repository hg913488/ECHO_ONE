#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Wi-Fi On
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Turns Wi-Fi on.
# @echo.phrases turn on wifi, turn wifi on, wi fi on, turn on wi fi

device=$(networksetup -listallhardwareports | awk '/Wi-Fi|AirPort/ { getline; print $2; exit }')
if [ -z "$device" ]; then echo "This Mac has no Wi-Fi."; exit 1; fi
networksetup -setairportpower "$device" on || exit 1
echo "Wi-Fi is on."
