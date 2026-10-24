#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP=${1:-"$ROOT/dist/ntfy-native.app"}
CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"

swift "$ROOT/scripts/generate-icon.swift"
iconutil -c icns "$ROOT/.build/ntfy-native.iconset" -o "$ROOT/.build/AppIcon.icns"
swift build -c release --package-path "$ROOT"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES"
cp "$ROOT/.build/release/ntfy-native" "$CONTENTS/MacOS/ntfy-native"
cp "$ROOT/.build/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp -R "$ROOT/.build/release/NtfyNative_NtfyNative.bundle" "$RESOURCES/"
cp -R "$ROOT/.build/release/NtfyNative_NtfyCore.bundle" "$RESOURCES/"
xcrun actool "$ROOT/.build/AppIconAssets.xcassets" \
    --compile "$RESOURCES" --platform macosx --minimum-deployment-target 13.0 \
    --app-icon AppIcon --output-partial-info-plist "$ROOT/.build/app-icon-info.plist" \
    --output-format human-readable-text --warnings --notices

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
    <key>CFBundleLocalizations</key>
    <array><string>zh-Hans</string><string>en</string><string>fr</string><string>de</string><string>es</string></array>
    <key>CFBundleExecutable</key><string>ntfy-native</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.timmy.ntfy-native</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>ntfy-native</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Local ad-hoc signature lets macOS recognize a coherent app bundle during development.
# Distribution still requires the developer's Developer ID signature and notarization.
codesign --force --deep --sign - "$APP"

printf 'Built %s\n' "$APP"
