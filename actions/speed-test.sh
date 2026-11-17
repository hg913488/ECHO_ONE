#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Speed Test
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Tests the internet speed with Apple's networkQuality, about 20 seconds.
# @echo.phrases internet speed, run a speed test, check my internet speed, how fast is my internet, check internet speed

result=$(networkQuality -c -M 20 2>/dev/null) || { echo "The speed test couldn't connect."; exit 1; }
down=$(echo "$result" | grep -Eo '"dl_throughput" *: *[0-9.]+' | grep -Eo '[0-9.]+$')
up=$(echo "$result" | grep -Eo '"ul_throughput" *: *[0-9.]+' | grep -Eo '[0-9.]+$')
if [ -z "$down" ]; then echo "The speed test didn't finish."; exit 1; fi
awk -v d="$down" -v u="${up:-0}" 'BEGIN { printf "%d megabits down, %d up.\n", d/1e6, u/1e6 }'
