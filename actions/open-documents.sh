#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Open Documents
# @raycast.mode silent
# @raycast.packageName Echo One
# @raycast.description Opens your Documents folder in Finder.
# @echo.phrases open my documents, open the documents folder, open my documents folder, show my documents

open "$HOME/Documents" || exit 1
echo "Opened Documents."
