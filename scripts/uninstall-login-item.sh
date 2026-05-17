#!/usr/bin/env bash
set -euo pipefail

LABEL="dev.local.mutepls"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ -f "$PLIST_PATH" ]]; then
    launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
    rm -f "$PLIST_PATH"
    echo "Removed login item $PLIST_PATH"
else
    echo "No login item found at $PLIST_PATH"
fi
