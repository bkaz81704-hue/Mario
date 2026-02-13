#!/bin/bash
cd "$(dirname "$0")"

APP_NAME="Super Mario"
LOVE_PATH="/Applications/love.app"

echo "Starting build..."

# Check for LÖVE in standard locations
if [ -d "/Applications/love.app" ]; then
    LOVE_PATH="/Applications/love.app"
elif [ -d "$HOME/Applications/love.app" ]; then
    LOVE_PATH="$HOME/Applications/love.app"
elif [ -d "$HOME/Downloads/love.app" ]; then
    LOVE_PATH="$HOME/Downloads/love.app"
else
    LOVE_PATH=""
fi

# If LÖVE app not found, just make a .love file (better than nothing)
if [ -z "$LOVE_PATH" ]; then
    echo "Could not find love.app in Applications or Downloads."
    echo "Creating a standard .love file instead."
    zip -9 -q -r "${APP_NAME}.love" . -x "*.git*" -x "*.DS_Store*" -x "*.command" -x "*.app*"
    echo "Created: ${APP_NAME}.love"
    open -R "${APP_NAME}.love" || echo "Check folder: $(pwd)"
    read -p "Press Enter to close..."
    exit 0
fi

echo "Building ${APP_NAME}.app using LÖVE from $LOVE_PATH..."

# 1. Copy love.app to create our new app bundle
rm -rf "${APP_NAME}.app"
cp -r "$LOVE_PATH" "${APP_NAME}.app"

# 2. Create the .love archive directly inside the new App bundle
# We exclude the app itself, hidden files, and scripts to keep it clean
mkdir -p "${APP_NAME}.app/Contents/Resources"
zip -9 -q -r "${APP_NAME}.app/Contents/Resources/${APP_NAME}.love" . -x "${APP_NAME}.app*" -x "*.git*" -x "*.DS_Store*" -x "*.command"

# 3. Update the App's internal name so it shows up correctly in the menu bar
PLIST="${APP_NAME}.app/Contents/Info.plist"
plutil -replace CFBundleName -string "${APP_NAME}" "$PLIST"
plutil -replace CFBundleDisplayName -string "${APP_NAME}" "$PLIST"
plutil -replace CFBundleIdentifier -string "com.benjaminkazemian.supermario" "$PLIST"

echo "SUCCESS! Created: ${APP_NAME}.app"
open -R "${APP_NAME}.app" || echo "Check folder: $(pwd)"
read -p "Press Enter to close..."