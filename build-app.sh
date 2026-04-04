#!/bin/bash
set -euo pipefail

APP_NAME="MOMO语音输入法"
EXECUTABLE_NAME="VoiceInputMac"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Building release binary..."
swift build -c release 2>&1

BINARY=".build/release/${EXECUTABLE_NAME}"
if [ ! -f "$BINARY" ]; then
    # Try arch-specific path
    BINARY=".build/arm64-apple-macosx/release/${EXECUTABLE_NAME}"
fi

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Cannot find release binary"
    exit 1
fi

echo "==> Assembling ${APP_NAME}.app..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "$BINARY" "${MACOS_DIR}/${EXECUTABLE_NAME}"
cp Resources/Info.plist "${CONTENTS_DIR}/Info.plist"

if [ -f Resources/VoiceInputMac.entitlements ]; then
    echo "==> Signing with entitlements..."
    codesign --force --sign - --entitlements Resources/VoiceInputMac.entitlements "${BUNDLE_DIR}"
else
    codesign --force --sign - "${BUNDLE_DIR}"
fi

echo ""
echo "==> Done! App bundle created at:"
echo "    $(pwd)/${BUNDLE_DIR}"
echo ""
echo "    You can run it with: open \"${BUNDLE_DIR}\""
