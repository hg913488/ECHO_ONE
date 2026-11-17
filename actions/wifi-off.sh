#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Wi-Fi Off
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Turns Wi-Fi off.
# @echo.phrases turn off wifi, turn wifi off, wi fi off, turn off wi fi

device=$(networksetup -listallhardwareports | awk '/Wi-Fi|AirPort/ { getline; print $2; exit }')
if [ -z "$device" ]; then echo "This Mac has no Wi-Fi."; exit 1; fi
networksetup -setairportpower "$device" off || exit 1
echo "Wi-Fi is off."
