#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/Apps/IlumMac"
DIST="$ROOT/dist"
APP="$DIST/Ilum.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Ilum.app packaging requires macOS." >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS"

swift build -c release --package-path "$PACKAGE"
BIN_DIR="$(swift build -c release --package-path "$PACKAGE" --show-bin-path)"
BINARY="$BIN_DIR/IlumMac"

if [[ ! -x "$BINARY" ]]; then
  echo "Release binary not found at $BINARY" >&2
  exit 1
fi

cp "$BINARY" "$MACOS/IlumMac"
chmod 755 "$MACOS/IlumMac"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Ilum</string>
    <key>CFBundleExecutable</key>
    <string>IlumMac</string>
    <key>CFBundleIdentifier</key>
    <string>local.ilum.desktop</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Ilum</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist" >/dev/null

# Development/CI builds are ad-hoc signed. Distribution notarization with an
# Apple Developer identity is a separate release concern and is not faked here.
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "Built and ad-hoc signed $APP"
echo "Launch with: open \"$APP\""
