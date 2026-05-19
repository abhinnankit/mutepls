#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MutePls.app"
SOURCE_APP="$PROJECT_DIR/dist/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"

"$PROJECT_DIR/scripts/package-app.sh"

if [[ ! -f "$SOURCE_APP/Contents/Resources/MutePls.icns" ]]; then
    echo "Missing app icon at $SOURCE_APP/Contents/Resources/MutePls.icns"
    exit 1
fi

rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
touch "$TARGET_APP" "$TARGET_APP/Contents" "$TARGET_APP/Contents/Info.plist" "$TARGET_APP/Contents/Resources/MutePls.icns"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if ! "$LSREGISTER" -f "$TARGET_APP"; then
    echo "Warning: LaunchServices could not register $TARGET_APP"
    echo "Raycast may not show the app until macOS indexes it."
fi

mdimport -i "$TARGET_APP" >/dev/null 2>&1 || true

echo "Installed $TARGET_APP"
echo "Open it with:"
echo "  open -n \"$TARGET_APP\""
