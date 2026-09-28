#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/TuneFlick.app"
VENDOR_DIR="$PROJECT_DIR/Vendor/media-control"
ADAPTER_DIR="$VENDOR_DIR/mediaremote-adapter"
FRAMEWORK_DIR="$APP_DIR/Contents/Frameworks/MediaRemoteAdapter.framework"
FRAMEWORK_CONTENTS="$FRAMEWORK_DIR/Versions/A"
MACOS_SDK="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$FRAMEWORK_CONTENTS/Resources" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/lib/media-control"
cp "$PROJECT_DIR/Resources/MediaRemoteAdapter-Info.plist" "$FRAMEWORK_CONTENTS/Resources/Info.plist"
ln -sfn A "$FRAMEWORK_DIR/Versions/Current"
ln -sfn Versions/Current/Resources "$FRAMEWORK_DIR/Resources"
ln -sfn Versions/Current/MediaRemoteAdapter "$FRAMEWORK_DIR/MediaRemoteAdapter"
cp "$VENDOR_DIR/bin/media-control" "$APP_DIR/Contents/Resources/media-control"
cp "$ADAPTER_DIR/bin/mediaremote-adapter.pl" "$APP_DIR/Contents/lib/media-control/mediaremote-adapter.pl"
chmod +x "$APP_DIR/Contents/Resources/media-control" "$APP_DIR/Contents/lib/media-control/mediaremote-adapter.pl"

xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -O2 \
    -arch x86_64 -arch arm64 -mmacosx-version-min=13.0 -isysroot "$MACOS_SDK" \
    -I "$ADAPTER_DIR/include" -I "$ADAPTER_DIR/src" \
    "$ADAPTER_DIR"/src/adapter/*.m "$ADAPTER_DIR"/src/private/*.m "$ADAPTER_DIR"/src/utility/*.m \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name @rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter \
    -o "$FRAMEWORK_CONTENTS/MediaRemoteAdapter"

xcrun clang -fobjc-arc -O2 -arch x86_64 -arch arm64 -mmacosx-version-min=13.0 -isysroot "$MACOS_SDK" \
    -I "$ADAPTER_DIR/src/test" "$ADAPTER_DIR"/src/test/*.m \
    -framework Foundation -framework MediaPlayer \
    -o "$APP_DIR/Contents/lib/media-control/MediaRemoteAdapterTestClient"

xcrun lipo "$FRAMEWORK_DIR/MediaRemoteAdapter" -verify_arch x86_64 arm64
xcrun lipo "$APP_DIR/Contents/lib/media-control/MediaRemoteAdapterTestClient" -verify_arch x86_64 arm64
xattr -cr "$FRAMEWORK_DIR"
codesign --force --sign - "$FRAMEWORK_DIR"
codesign --force --sign - "$APP_DIR/Contents/lib/media-control/MediaRemoteAdapterTestClient"
