#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Disk Space
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Says how much space is free on the Mac's disk.
# @echo.phrases how much space, free space, how much disk space, how much storage, storage left, how much space do i have

volume=/System/Volumes/Data
[ -d "$volume" ] || volume=/
df -k "$volume" | awk 'NR==2 { printf "%d GB free of %d GB.\n", $4*1024/1e9, $2*1024/1e9 }'
