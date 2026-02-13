#!/bin/bash
cd "$(dirname "$0")"

# 1. Try standard Application path
if [ -f "/Applications/love.app/Contents/MacOS/love" ]; then
    "/Applications/love.app/Contents/MacOS/love" . &
    exit
fi

# 1.5 Try user Application path (e.g. installed in /Users/username/Applications)
if [ -f "$HOME/Applications/love.app/Contents/MacOS/love" ]; then
    "$HOME/Applications/love.app/Contents/MacOS/love" . &
    exit
fi

# 2. Try system path (e.g. installed via Homebrew)
if command -v love &> /dev/null; then
    love . &
    exit
fi

echo "Error: Could not find LÖVE. Please ensure love.app is in /Applications."
read -p "Press Enter to close..."