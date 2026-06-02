#!/usr/bin/env bash
# Builds the Momentum menu bar app into a signed .app bundle.
# Usage: ./build.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")"

# Build against the macOS 26 SDK (Liquid Glass) when available, so standard
# controls adopt the current design language. The default Xcode here is 16.2
# (macOS 15 SDK), which renders the legacy appearance; the Command Line Tools
# ship the macOS 26 SDK. Falls back to the default toolchain if absent.
if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk" ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  echo "[sdk] using macOS 26 SDK via Command Line Tools (Liquid Glass)"
fi

APP_NAME="Momentum"
BUNDLE_ID="io.bransfer.momentum"
CONFIG="${1:-release}"

# Use a dedicated scratch path so the app build (macOS 26 SDK / CLT toolchain)
# doesn't collide with `swift test`, which must run under full Xcode (XCTest /
# Testing ship only with Xcode, not the Command Line Tools).
echo "[1/3] swift build (${CONFIG})"
swift build -c "${CONFIG}" --product "${APP_NAME}" --scratch-path ".build-app"
BIN=".build-app/${CONFIG}/${APP_NAME}"
[ -f "${BIN}" ] || { echo "build failed: ${BIN} missing"; exit 1; }

APP="${APP_NAME}.app"
echo "[2/3] assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/${APP_NAME}"

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Momentum connects to your Sennheiser Momentum 4 to read and control noise cancellation and transparency.</string>
</dict>
</plist>
PLIST

echo "[3/3] codesigning (ad-hoc)"
codesign --force --sign - "${APP}"

echo "OK: $(pwd)/${APP}"
echo "run: open ${APP}"
