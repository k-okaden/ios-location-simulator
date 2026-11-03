#!/bin/zsh
# 位置シミュレータ.app をビルドする: ./build.sh  →  locsim/build/位置シミュレータ.app
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP="../build/位置シミュレータ.app"
TMP="$(mktemp -d)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -target "$(uname -m)-apple-macos13.0" main.swift -o "$APP/Contents/MacOS/LocSim"
cp ../server.py ../index.html "$APP/Contents/Resources/"

# アイコン
xcrun swiftc icon.swift -o "$TMP/icon" && "$TMP/icon" "$TMP/icon.png"
mkdir "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>位置シミュレータ</string>
  <key>CFBundleDisplayName</key><string>位置シミュレータ</string>
  <key>CFBundleIdentifier</key><string>local.locsim</string>
  <key>CFBundleExecutable</key><string>LocSim</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
EOF

codesign --force --deep -s - "$APP"
rm -rf "$TMP"
echo "built: $(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
