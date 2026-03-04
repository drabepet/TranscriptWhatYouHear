#!/usr/bin/env bash
# create_app.sh — build TranscriptWhatYouHear.app and install it to ~/Applications
#
# The resulting app can be:
#   • Double-clicked in Finder
#   • Added to Login Items (System Settings → General → Login Items)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DEST="$HOME/Applications/TranscriptWhatYouHear.app"
CONTENTS="$DEST/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# ── Build Swift binary ───────────────────────────────────────────────────────
echo "🔨  Building TranscriptWhatYouHear (Swift)…"
cd "$SCRIPT_DIR"
swift build -c release 2>&1 | tail -5

BINARY="$SCRIPT_DIR/.build/release/TranscriptWhatYouHear"
if [ ! -f "$BINARY" ]; then
    echo "❌  Build failed — binary not found"
    exit 1
fi

# ── Build bundle structure ────────────────────────────────────────────────────
echo "📦  Creating .app bundle…"
rm -rf "$DEST"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BINARY" "$MACOS/TranscriptWhatYouHear"
chmod +x "$MACOS/TranscriptWhatYouHear"

# Copy docs.html into Resources
if [ -f "$SCRIPT_DIR/docs.html" ]; then
    cp "$SCRIPT_DIR/docs.html" "$RESOURCES/docs.html"
fi

# ── Info.plist ────────────────────────────────────────────────────────────────
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TranscriptWhatYouHear</string>
    <key>CFBundleIdentifier</key>
    <string>com.transcriptwhatyouhear.app</string>
    <key>CFBundleName</key>
    <string>TranscriptWhatYouHear</string>
    <key>CFBundleDisplayName</key>
    <string>TranscriptWhatYouHear</string>
    <key>CFBundleVersion</key>
    <string>2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <!-- Hide from Dock — menu bar only app -->
    <key>LSUIElement</key>
    <true/>
    <!-- Privacy descriptions (shown in permission dialogs) -->
    <key>NSMicrophoneUsageDescription</key>
    <string>TranscriptWhatYouHear records your voice to transcribe speech into text.</string>
</dict>
</plist>
PLIST

# ── App icon (optional — uses system mic icon if this fails) ─────────────────
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
    /usr/libexec/PlistBuddy -c \
        "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || true
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✅  TranscriptWhatYouHear.app installed to ~/Applications"
echo ""
echo "Next steps:"
echo "  • Double-click ~/Applications/TranscriptWhatYouHear.app to launch"
echo "  • Or: open ~/Applications/TranscriptWhatYouHear.app"
echo ""
echo "To start automatically on login:"
echo "  System Settings → General → Login Items → (+) → TranscriptWhatYouHear.app"
