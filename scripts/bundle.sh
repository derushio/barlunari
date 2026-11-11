#!/usr/bin/env bash
# release ビルドの BarlunariApp から build/Barlunari.app を組み立て、scripts/codesign.sh で署名する。
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

# Sources/BarlunariInfrastructure/AppIdentity.swift と同じ値にする。
# 同じバンドル ID の .app が複数のパスにあると、LaunchServices が別のコピーを選び、システム設定がそのコピーに許可を付ける。
# worktree を消すとそのパスがなくなるため、worktree で組み立てた .app には worktree 名を付けた別のバンドル ID を付ける。
BUNDLE_ID="io.github.derushio.Barlunari"
if [ "$(git -C "$ROOT" rev-parse --absolute-git-dir)" != "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)" ]; then
    BUNDLE_ID="$BUNDLE_ID.worktree.$(basename "$ROOT" | LC_ALL=C tr -c 'A-Za-z0-9.\n' '-')"
fi

# LSUIElement を true にして、Dock とアプリ切り替えに出さない。
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
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
"$ROOT/scripts/codesign.sh" "$APP"
echo "作成した: $APP"
