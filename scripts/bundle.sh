#!/usr/bin/env bash
# release ビルドの BarlunariApp から build/Barlunari.app を組み立て、ad-hoc 署名する。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Barlunari.app"
VERSION="${BARLUNARI_VERSION:-0.1.0}"

cd "$ROOT"
swift build -c release --product BarlunariApp
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BarlunariApp" "$APP/Contents/MacOS/Barlunari"

# LSUIElement を true にして、Dock とアプリ切り替えに出さない。
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>io.github.derushio.Barlunari</string>
    <key>CFBundleName</key>
    <string>Barlunari</string>
    <key>CFBundleDisplayName</key>
    <string>Barlunari</string>
    <key>CFBundleExecutable</key>
    <string>Barlunari</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>メニューバーのカレンダーに予定を表示するために、カレンダーを読み取ります。</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --verbose=2 "$APP"
echo "作成した: $APP"
