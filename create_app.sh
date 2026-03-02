#!/usr/bin/env bash
# create_app.sh — build VoiceClaude.app and install it to ~/Applications
#
# Run once after setup.sh. The resulting app can be:
#   • Double-clicked in Finder
#   • Added to Login Items (System Settings → General → Login Items)
#   • Dragged to the Dock
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$SCRIPT_DIR/.venv"
PYTHON="$VENV/bin/python"
MAIN="$SCRIPT_DIR/voice_claude.py"

DEST="$HOME/Applications/VoiceClaude.app"
CONTENTS="$DEST/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# ── Sanity checks ─────────────────────────────────────────────────────────────
if [ ! -f "$PYTHON" ]; then
    echo "❌  Virtual environment not found. Run ./setup.sh first."
    exit 1
fi

# ── Build bundle structure ────────────────────────────────────────────────────
echo "🔧  Building VoiceClaude.app…"
rm -rf "$DEST"
mkdir -p "$MACOS" "$RESOURCES"

# ── Launcher script ───────────────────────────────────────────────────────────
cat > "$MACOS/VoiceClaude" << LAUNCHER
#!/bin/bash
exec "$PYTHON" "$MAIN"
LAUNCHER
chmod +x "$MACOS/VoiceClaude"

# ── Info.plist ────────────────────────────────────────────────────────────────
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VoiceClaude</string>
    <key>CFBundleIdentifier</key>
    <string>com.voiceclaude.app</string>
    <key>CFBundleName</key>
    <string>VoiceClaude</string>
    <key>CFBundleDisplayName</key>
    <string>Voice Claude</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <!-- Hide from Dock — menu bar only app -->
    <key>LSUIElement</key>
    <true/>
    <!-- Privacy descriptions (shown in permission dialogs) -->
    <key>NSMicrophoneUsageDescription</key>
    <string>Voice Claude records your voice to transcribe speech into text.</string>
</dict>
</plist>
PLIST

# ── Copy mic icon as app icon (icns) if sips is available ────────────────────
IDLE_PNG="$SCRIPT_DIR/icons/idleTemplate.png"
if [ -f "$IDLE_PNG" ] && command -v sips &>/dev/null; then
    ICONSET="$RESOURCES/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for SIZE in 16 32 64 128 256 512; do
        sips -z $SIZE $SIZE "$IDLE_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" -s formatOptions low &>/dev/null
        DOUBLE=$((SIZE * 2))
        sips -z $DOUBLE $DOUBLE "$IDLE_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" -s formatOptions low &>/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns" 2>/dev/null && \
        echo "  ✅  App icon generated" || echo "  ⚠️   iconutil failed — app will use default icon"
    rm -rf "$ICONSET"

    # Tell the bundle which icon to use
    /usr/libexec/PlistBuddy -c \
        "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || true
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✅  VoiceClaude.app installed to ~/Applications"
echo ""
echo "Next steps:"
echo "  • Double-click ~/Applications/VoiceClaude.app to launch"
echo "  • Or: open ~/Applications/VoiceClaude.app"
echo ""
echo "To start automatically on login:"
echo "  System Settings → General → Login Items → (+) → VoiceClaude.app"
