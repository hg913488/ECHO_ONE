#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Open Downloads
# @raycast.mode silent
# @raycast.packageName Echo One
# @raycast.description Opens your Downloads folder in Finder.
# @echo.phrases open my downloads, open the downloads folder, open my downloads folder, show my downloads

open "$HOME/Downloads" || exit 1
echo "Opened Downloads."
