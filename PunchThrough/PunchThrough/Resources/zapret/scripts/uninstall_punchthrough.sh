#!/bin/bash
# PunchThrough Zapret service uninstaller
set -e
TARGET_DIR="/opt/punchthrough-zapret"
PLIST_PATH="/Library/LaunchDaemons/com.punchthrough.zapret.plist"
SUDOERS_FILE="/etc/sudoers.d/punchthrough-zapret"

# Stop the service first
if [ -f "$TARGET_DIR/init.d/macos/zapret" ]; then
    "$TARGET_DIR/init.d/macos/zapret" stop 2>/dev/null || true
fi
pkill -9 tpws 2>/dev/null || true

# Unload + remove LaunchDaemon
if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
fi

# Sudoers rule
rm -f "$SUDOERS_FILE"

# Files
rm -rf "$TARGET_DIR"

echo "PunchThrough Zapret service uninstalled."
exit 0
