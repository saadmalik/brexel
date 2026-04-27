#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Brexel"
EXECUTABLE_NAME="Brexel"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Resources/brexel-icon.png"
ICON_NAME="AppIcon"

build_icns() {
  local source="$1"
  local out_icns="$2"

  if [[ ! -f "$source" ]]; then
    echo "Icon source not found: $source" >&2
    return 1
  fi

  local iconset
  iconset="$(mktemp -d)/$ICON_NAME.iconset"
  mkdir -p "$iconset"

  # Standard macOS app iconset: 16/32/128/256/512 at 1x and 2x.
  for spec in "16 16" "16 32" "32 32" "32 64" "128 128" "128 256" "256 256" "256 512" "512 512" "512 1024"; do
    read -r size px <<<"$spec"
    local suffix=""
    if [[ "$px" -gt "$size" ]]; then suffix="@2x"; fi
    sips -z "$px" "$px" "$source" --out "$iconset/icon_${size}x${size}${suffix}.png" >/dev/null
  done

  iconutil -c icns "$iconset" -o "$out_icns"
  rm -rf "$(dirname "$iconset")"
}

find_codesign_identity() {
  local pattern="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' -v pattern="$pattern" 'index($0, pattern) { print $2; exit }'
}

default_codesign_identity() {
  if [[ -n "${BREX_CODESIGN_IDENTITY:-}" ]]; then
    echo "$BREX_CODESIGN_IDENTITY"
    return
  fi

  local identity
  identity="$(find_codesign_identity "Brexel Local Signing")"
  if [[ -n "$identity" ]]; then
    echo "$identity"
    return
  fi

  identity="$(find_codesign_identity "Developer ID Application:")"
  if [[ -n "$identity" ]]; then
    echo "$identity"
    return
  fi

  identity="$(find_codesign_identity "Apple Development:")"
  if [[ -n "$identity" ]]; then
    echo "$identity"
  fi
}

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp ".build/release/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"

build_icns "$ICON_SOURCE" "$RESOURCES_DIR/$ICON_NAME.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.brexel</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  SIGNING_IDENTITY="$(default_codesign_identity)"
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "Signing with: $SIGNING_IDENTITY"
    codesign --force --deep --timestamp=none --sign "$SIGNING_IDENTITY" "$APP_DIR" >/dev/null
  else
    echo "Signing ad-hoc. Set BREX_CODESIGN_IDENTITY to use a persistent identity."
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
  fi
fi

echo "Built $APP_DIR"
