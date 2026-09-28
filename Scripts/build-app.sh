#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

ARCHITECTURES=(x86_64 arm64)
MACOS_SDK="$(xcrun --sdk macosx --show-sdk-path)"
BINARIES=()

for architecture in "${ARCHITECTURES[@]}"; do
    triple="${architecture}-apple-macosx"
    architecture_build_dir="$PROJECT_DIR/.build/universal/$architecture"
    # SwiftPM's build manifest must not be shared between target triples.
    swift build -c release --scratch-path "$architecture_build_dir" --triple "$triple" --sdk "$MACOS_SDK"
    bin_dir="$(swift build -c release --scratch-path "$architecture_build_dir" --triple "$triple" --sdk "$MACOS_SDK" --show-bin-path)"
    BINARIES+=("$bin_dir/TuneFlick")
done

APP_DIR="$PROJECT_DIR/build/TuneFlick.app"
ICONSET_DIR="$PROJECT_DIR/build/AppIcon.iconset"
APP_ICON_SOURCE="$PROJECT_DIR/Resources/AppIcon-v2.png"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICONSET_DIR"

xcrun lipo -create "${BINARIES[@]}" -output "$APP_DIR/Contents/MacOS/TuneFlick"
xcrun lipo "$APP_DIR/Contents/MacOS/TuneFlick" -verify_arch "${ARCHITECTURES[@]}"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$APP_ICON_SOURCE" "$APP_DIR/Contents/Resources/AppIcon.png"
cp "$PROJECT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
cp "$PROJECT_DIR/THIRD_PARTY_LICENSES.md" "$APP_DIR/Contents/Resources/THIRD_PARTY_LICENSES.md"
bash "$PROJECT_DIR/Scripts/build-media-control.sh"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
touch "$APP_DIR"

# File-provider metadata can arrive just after a bundle is assembled.
app_signed=false
for signing_attempt in 1 2 3; do
    xattr -cr "$APP_DIR"
    if codesign --force --sign - --requirements '=designated => identifier "com.tuneflick.app"' "$APP_DIR" &&
       codesign --verify --deep --strict --all-architectures "$APP_DIR"; then
        app_signed=true
        break
    fi
    sleep 1
done
if [ "$app_signed" != true ]; then
    echo "Could not sign TuneFlick.app. Check the bundle's extended attributes and rebuild." >&2
    exit 1
fi

echo "Built Universal 2 (x86_64 + arm64): $APP_DIR"
