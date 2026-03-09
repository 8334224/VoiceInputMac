#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME="VoiceInputMac"
DISPLAY_NAME="MOMO语音输入法"
VERSION="0.1.0"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
ZIP_PATH="$ROOT_DIR/dist/${APP_NAME}-${VERSION}-macOS.zip"
CACHE_DIR="$ROOT_DIR/.codex-cache"
ICON_SCRIPT="$ROOT_DIR/scripts/generate_app_icon.swift"
ICNS_PATH="$ROOT_DIR/Resources/VoiceInputMac.icns"

cd "$ROOT_DIR"
mkdir -p "$CACHE_DIR/clang" "$CACHE_DIR/swiftpm"
swift "$ICON_SCRIPT" "$ROOT_DIR"

env \
  HOME="$ROOT_DIR" \
  SWIFTPM_CUSTOM_CACHE_PATH="$CACHE_DIR/swiftpm" \
  CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang" \
  swift build -c release

BIN_DIR=$(env \
  HOME="$ROOT_DIR" \
  SWIFTPM_CUSTOM_CACHE_PATH="$CACHE_DIR/swiftpm" \
  CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang" \
  swift build -c release --show-bin-path)
BIN_PATH="$BIN_DIR/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ICNS_PATH" "$APP_DIR/Contents/Resources/${APP_NAME}.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.adi.voiceinputmac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>语音输入需要访问麦克风。</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>语音输入需要使用苹果语音识别能力将你的讲话转成文字。</string>
</dict>
</plist>
PLIST

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Built app bundle at: $APP_DIR"
echo "Built zip archive at: $ZIP_PATH"
