#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [path/to/TuneFlick.app]" >&2
    exit 1
fi
if [ "$#" -eq 0 ]; then
    bash "$PROJECT_DIR/Scripts/build-app.sh"
fi
APP_DIR="${1:-$PROJECT_DIR/build/TuneFlick.app}"
APP_INFO="$APP_DIR/Contents/Info.plist"
if [ ! -f "$APP_INFO" ]; then
    echo "TuneFlick.app was not found at $APP_DIR. Run Scripts/build-app.sh or pass a built app." >&2
    exit 1
fi

APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_INFO")"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO")"
MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_INFO")"
INSTALLER_RESOURCES="$PROJECT_DIR/Resources/Installer"
INSTALLER_MINIMUM_MACOS="$(xmllint --xpath 'string(/installer-gui-script/volume-check/allowed-os-versions/os-version/@min)' "$INSTALLER_RESOURCES/Distribution.xml")"
if [ "$APP_IDENTIFIER" != "com.tuneflick.app" ] || [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "The app at $APP_DIR has an unexpected identifier or version. Use a TuneFlick release build." >&2
    exit 1
fi
if [ "$MINIMUM_MACOS" != "$INSTALLER_MINIMUM_MACOS" ]; then
    echo "Installer and app macOS requirements differ. Update Resources/Installer/Distribution.xml to match LSMinimumSystemVersion." >&2
    exit 1
fi

mkdir -p "$PROJECT_DIR/.build" "$PROJECT_DIR/build/release-artifacts"
STAGING_DIR="$(mktemp -d "$PROJECT_DIR/.build/installer.XXXXXX")"
STAGING_VOLUME="$STAGING_DIR/volume"
PAYLOAD_ROOT="$STAGING_VOLUME/payload"
STAGING_MOUNTED=false
cleanup() {
    if [ "$STAGING_MOUNTED" = true ]; then
        if ! hdiutil detach -quiet "$STAGING_VOLUME"; then
            echo "Could not unmount installer staging at $STAGING_VOLUME. Eject that volume before removing $STAGING_DIR." >&2
            return 1
        fi
    fi
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

# A read-only staging volume prevents file providers from adding Finder metadata
# to signed bundles while pkgbuild reads them. Keep the image inside the project.
hdiutil create -quiet -size 64m -fs HFS+ -volname TuneFlickPayload "$STAGING_DIR/payload.dmg"
mkdir -p "$STAGING_VOLUME"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$STAGING_VOLUME" "$STAGING_DIR/payload.dmg"
STAGING_MOUNTED=true
STAGED_APP="$PAYLOAD_ROOT/Applications/TuneFlick.app"
mkdir -p "$PAYLOAD_ROOT/Applications"

ditto --noextattr --norsrc "$APP_DIR" "$STAGED_APP"
xattr -cr "$STAGED_APP"
codesign --verify --deep --strict --all-architectures "$STAGED_APP"
for binary in \
    "$STAGED_APP/Contents/MacOS/TuneFlick" \
    "$STAGED_APP/Contents/Frameworks/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
    "$STAGED_APP/Contents/lib/media-control/MediaRemoteAdapterTestClient"; do
    xcrun lipo "$binary" -verify_arch x86_64 arm64
done

xattr -cr "$PAYLOAD_ROOT"
hdiutil detach -quiet "$STAGING_VOLUME"
STAGING_MOUNTED=false
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$STAGING_VOLUME" "$STAGING_DIR/payload.dmg"
STAGING_MOUNTED=true
# Relocation must stay disabled: an app in Downloads is not the install target.
pkgbuild --root "$PAYLOAD_ROOT" \
    --component-plist "$INSTALLER_RESOURCES/Components.plist" \
    --identifier com.tuneflick.installer \
    --version "$APP_VERSION" \
    --install-location / \
    --ownership recommended \
    "$STAGING_DIR/TuneFlick.pkg"

INSTALLER_PATH="$PROJECT_DIR/build/release-artifacts/TuneFlick-$APP_VERSION-universal.pkg"
productbuild --distribution "$INSTALLER_RESOURCES/Distribution.xml" \
    --package-path "$STAGING_DIR" \
    --identifier com.tuneflick.installer \
    --version "$APP_VERSION" \
    "$INSTALLER_PATH"

bash "$PROJECT_DIR/Scripts/verify-installer.sh" "$INSTALLER_PATH"

echo "Built Universal installer: $INSTALLER_PATH"
echo "Install location: /Applications/TuneFlick.app"
echo "This package is not Developer ID signed or notarized."
