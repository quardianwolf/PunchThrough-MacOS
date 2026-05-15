#!/bin/bash
# PunchThrough Zapret service installer
# Bundles zapret (https://github.com/bol-van/zapret)

set -e
TARGET_DIR="/opt/punchthrough-zapret"
LOG="/tmp/punchthrough_install.log"
echo "Starting PunchThrough Zapret install..." > "$LOG"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Script lives at zapret/scripts/, zapret root is one level up
SOURCE_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "Script Dir: $SCRIPT_DIR" >> "$LOG"
echo "Source Dir: $SOURCE_DIR" >> "$LOG"

if [ ! -f "$SOURCE_DIR/tpws/tpws" ]; then
    echo "ERROR: tpws binary not found at $SOURCE_DIR/tpws/tpws" | tee -a "$LOG"
    exit 1
fi

# Stop any previous instance before overwriting
if [ -f /Library/LaunchDaemons/com.punchthrough.zapret.plist ]; then
    launchctl unload /Library/LaunchDaemons/com.punchthrough.zapret.plist 2>/dev/null || true
fi
pkill -9 tpws 2>/dev/null || true

# Fresh install
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
cp -R "$SOURCE_DIR/." "$TARGET_DIR/"

# Write working config (tlsrec+split — verified against Turkish DPI + Discord updater)
cat > "$TARGET_DIR/config_custom" <<'CONFIGEOF'
MODE_FILTER=autohostlist
TPWS_ENABLE=1
TPWS_SOCKS_ENABLE=1
TPWS_PORTS=80,443
INIT_APPLY_FW=1
DISABLE_IPV6=1
GZIP_LISTS=0
GETLIST=get_refilter_domains.sh
TPWS_OPT="
--filter-tcp=80 --methodeol <HOSTLIST> --new
--filter-tcp=443 --tlsrec=sni --split-pos=1,midsld <HOSTLIST>
"
CONFIGEOF
chmod 644 "$TARGET_DIR/config_custom"

# Hook custom config into main config
CONFIG_FILE="$TARGET_DIR/config"
if [ -f "$CONFIG_FILE" ] && ! grep -q "config_custom" "$CONFIG_FILE"; then
    echo "" >> "$CONFIG_FILE"
    echo "# PunchThrough custom strategy" >> "$CONFIG_FILE"
    echo ". \"$TARGET_DIR/config_custom\"" >> "$CONFIG_FILE"
elif [ ! -f "$CONFIG_FILE" ]; then
    # No default config — create one that only loads custom
    cp "$TARGET_DIR/config.default" "$CONFIG_FILE" 2>/dev/null || true
    echo "" >> "$CONFIG_FILE"
    echo ". \"$TARGET_DIR/config_custom\"" >> "$CONFIG_FILE"
fi

mkdir -p "$TARGET_DIR/ipset"
touch "$TARGET_DIR/ipset/zapret-hosts-user.txt"
touch "$TARGET_DIR/ipset/zapret-hosts-auto.txt"
touch "$TARGET_DIR/ipset/zapret-hosts-user-exclude.txt"
touch "$TARGET_DIR/ipset/zapret-hosts.txt"
chmod +x "$TARGET_DIR/ipset/"*.sh 2>/dev/null || true

# Try to pull refilter hostlist (YouTube + Discord etc.). Don't fail the install if offline.
echo "Downloading hostlist..." >> "$LOG"
(export GZIP_LISTS=0 && cd "$TARGET_DIR/ipset" && ./get_refilter_domains.sh >>"$LOG" 2>&1) || echo "Warning: hostlist download failed; using empty list" >> "$LOG"
chmod 644 "$TARGET_DIR/ipset/"*.txt 2>/dev/null || true
if [ ! -s "$TARGET_DIR/ipset/zapret-hosts-user.txt" ]; then
    echo "nonexistent.domain" >> "$TARGET_DIR/ipset/zapret-hosts-user.txt"
fi

# Make binaries executable, strip quarantine
xattr -d com.apple.quarantine -r "$TARGET_DIR" 2>/dev/null || true
chmod +x "$TARGET_DIR/init.d/macos/zapret"
chmod +x "$TARGET_DIR/tpws/tpws"

# Sudoers: allow controlling the service without password
SUDOERS_FILE="/etc/sudoers.d/punchthrough-zapret"
echo "ALL ALL=(ALL) NOPASSWD: $TARGET_DIR/init.d/macos/zapret" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
echo "Sudoers rule written to $SUDOERS_FILE" >> "$LOG"

# LaunchDaemon for autostart at boot (runs as root)
PLIST_PATH="/Library/LaunchDaemons/com.punchthrough.zapret.plist"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.punchthrough.zapret</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TARGET_DIR/init.d/macos/zapret</string>
        <string>start</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardErrorPath</key>
    <string>/tmp/punchthrough-zapret.error.log</string>
    <key>StandardOutPath</key>
    <string>/tmp/punchthrough-zapret.out.log</string>
</dict>
</plist>
EOF
chmod 644 "$PLIST_PATH"
launchctl load -w "$PLIST_PATH" 2>>"$LOG" || true

echo "PunchThrough Zapret service installed." | tee -a "$LOG"
exit 0
