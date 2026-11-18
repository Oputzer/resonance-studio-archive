#!/bin/zsh
# Double-click to start the Playlist Zipper and open it in your browser.
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$HOME/.nvm/versions/node/v24.14.1/bin:$PATH"
lsof -ti tcp:4321 >/dev/null 2>&1 || (node server.js &)
sleep 1
open "http://localhost:4321"
echo "Playlist Zipper is running. Close this window to stop it."
wait
