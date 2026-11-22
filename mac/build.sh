#!/bin/bash
# Mac receiver (keyboard keys + a small browser racing game): build, bundle, sign, put on the Desktop.
# Optional: FACECONTROLLER_MAC_BUNDLE_ID in ../Config/local.env. (TR) Mac alıcısı: derle, paketle, imzala, masaüstüne koy.
# Geliştirici sertifikasıyla imzalanır: Erişilebilirlik izni her derlemede kaybolmasın.
set -euo pipefail
cd "$(dirname "$0")"
[ -f ../Config/local.env ] && source ../Config/local.env
BUNDLE_ID="${FACECONTROLLER_MAC_BUNDLE_ID:-com.example.facecontroller.mac}"
APP="build/Yüz Direksiyon.app"
rm -rf build; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/YuzDireksiyon" main.swift ../iOS/FaceController/Protocol.swift \
  -framework SwiftUI -framework Network -framework ApplicationServices
cp game/yaris.html "$APP/Contents/Resources/yaris.html"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Yüz Direksiyon</string>
  <key>CFBundleDisplayName</key><string>Yüz Direksiyon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>YuzDireksiyon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>To receive face steering/gas/brake values from the iPhone app.</string>
  <key>NSBonjourServices</key><array><string>_denemeyuz._udp</string></array>
</dict></plist>
PL
KIMLIK=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
if [ -n "$KIMLIK" ]; then codesign --force -s "$KIMLIK" "$APP" >/dev/null 2>&1; else codesign --force -s - "$APP" >/dev/null 2>&1; fi
rm -rf "$HOME/Desktop/Yüz Direksiyon.app"
cp -R "$APP" "$HOME/Desktop/Yüz Direksiyon.app"
echo "Masaüstünde: $HOME/Desktop/Yüz Direksiyon.app"
