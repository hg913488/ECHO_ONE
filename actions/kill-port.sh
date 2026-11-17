#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Kill Port
# @raycast.mode compact
# @raycast.packageName Echo One
# @raycast.description Stops whatever is listening on a port, like a stuck dev server.
# @raycast.argument1 { "type": "text", "placeholder": "port, like 3000" }
# @echo.phrases stop port, free port, free up port, stop whatever is on port, kill whatever is on port

port=$(echo "$1" | tr -cd '0-9')
if [ -z "$port" ]; then echo "Say a port number, like kill port 3000."; exit 1; fi
pids=$(lsof -nP -t -iTCP:"$port" -sTCP:LISTEN)
if [ -z "$pids" ]; then echo "Nothing is running on port $port."; exit 0; fi
names=$(for pid in $pids; do basename "$(ps -p "$pid" -o comm=)"; done | sort -u | paste -sd ',' - | sed 's/,/, /g')
kill $pids || exit 1
echo "Stopped $names on port $port."
