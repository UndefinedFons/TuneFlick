#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    echo "Usage: $0 path/to/TuneFlick-universal.pkg" >&2
    exit 1
fi
INSTALLER_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
mkdir -p "$PROJECT_DIR/.build"
CHECK_DIR="$(mktemp -d "$PROJECT_DIR/.build/installer-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT

pkgutil --expand "$INSTALLER_PATH" "$CHECK_DIR/raw"
DISTRIBUTION="$CHECK_DIR/raw/Distribution"
PACKAGE_INFO="$CHECK_DIR/raw/TuneFlick.pkg/PackageInfo"
PAYLOAD_ARCHIVE="$CHECK_DIR/raw/TuneFlick.pkg/Payload"

require_xml() {
    local file="$1" expression="$2" expected="$3"
    local actual
    actual="$(xmllint --xpath "$expression" "$file")"
    if [ "$actual" != "$expected" ]; then
        echo "Installer check failed in $file: $expression returned '$actual', expected '$expected'. Rebuild with Scripts/build-installer.sh." >&2
        exit 1
    fi
}

require_xml "$DISTRIBUTION" 'string(/installer-gui-script/title)' TuneFlick
require_xml "$DISTRIBUTION" 'string(/installer-gui-script/options/@hostArchitectures)' x86_64,arm64
require_xml "$DISTRIBUTION" 'string(/installer-gui-script/domains/@enable_localSystem)' true
require_xml "$DISTRIBUTION" 'string(/installer-gui-script/domains/@enable_currentUserHome)' false
require_xml "$DISTRIBUTION" 'string(/installer-gui-script/domains/@enable_anywhere)' false
require_xml "$DISTRIBUTION" 'count(//relocate | //locator | //script | //choice/@customLocation)' 0
require_xml "$PACKAGE_INFO" 'string(/pkg-info/@identifier)' com.tuneflick.installer
require_xml "$PACKAGE_INFO" 'string(/pkg-info/@install-location)' /
require_xml "$PACKAGE_INFO" 'string(/pkg-info/@relocatable)' false
require_xml "$PACKAGE_INFO" 'count(/pkg-info/relocate/* | /pkg-info/scripts/*)' 0
require_xml "$PACKAGE_INFO" 'string(/pkg-info/bundle[@id="com.tuneflick.app"]/@path)' ./Applications/TuneFlick.app
if [ -e "$CHECK_DIR/raw/TuneFlick.pkg/Scripts" ]; then
    echo "Unexpected installer scripts in $INSTALLER_PATH. The TuneFlick installer must contain only the application payload." >&2
    exit 1
fi

# Inspect the archived metadata before extraction into a file-provider folder.
/usr/bin/ruby - "$PAYLOAD_ARCHIVE" <<'RUBY'
archive = ARGV.fetch(0)
entries = IO.popen(['tar', '-tf', archive], &:read).lines.map(&:chomp)
abort 'Unable to read installer payload.' unless $?.success?
entries.each do |path|
  abort "Unexpected parent-directory reference in installer destination: #{path}" if path.split('/').include?('..')
  unless path == '.' || path == './Applications' || path == './._Applications' ||
      path == './Applications/._TuneFlick.app' || path == './Applications/TuneFlick.app' ||
      path.start_with?('./Applications/TuneFlick.app/')
    abort "Unexpected installer destination: #{path}"
  end
  next unless File.basename(path).start_with?('._')
  data = IO.popen(['tar', '-xOf', archive, path], &:read).b
  abort "Unable to read archived metadata for #{path}." unless $?.success?
  abort "Invalid AppleDouble metadata for #{path}." unless data.bytesize >= 26 && data.unpack('N').first == 0x00051607
  count = data.byteslice(24, 2).unpack('n').first
  count.times do |index|
    record = data.byteslice(26 + index * 12, 12)
    abort "Incomplete metadata for #{path}." unless record && record.bytesize == 12
    identifier, offset, length = record.unpack('N3')
    bytes = data.byteslice(offset, length)
    abort "Incomplete metadata payload for #{path}." unless bytes && bytes.bytesize == length
    if (identifier == 2 && length > 0) ||
        (identifier == 9 && (length < 32 || bytes.byteslice(0, 32).bytes.any? { |byte| byte != 0 }))
      abort "Finder metadata or a resource fork was archived for #{path}. Rebuild the installer after clearing staging metadata."
    end
  end
end
RUBY

pkgutil --expand-full "$INSTALLER_PATH" "$CHECK_DIR/expanded"
PAYLOAD_ROOT="$CHECK_DIR/expanded/TuneFlick.pkg/Payload"
APP_DIR="$PAYLOAD_ROOT/Applications/TuneFlick.app"
APP_INFO="$APP_DIR/Contents/Info.plist"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO")"
MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_INFO")"
require_xml "$PACKAGE_INFO" 'string(/pkg-info/@version)' "$APP_VERSION"
require_xml "$DISTRIBUTION" 'string(/installer-gui-script/volume-check/allowed-os-versions/os-version/@min)' "$MINIMUM_MACOS"
for binary in \
    "$APP_DIR/Contents/MacOS/TuneFlick" \
    "$APP_DIR/Contents/Frameworks/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
    "$APP_DIR/Contents/lib/media-control/MediaRemoteAdapterTestClient"; do
    xcrun lipo "$binary" -verify_arch x86_64 arm64
done
for document in LICENSE THIRD_PARTY_LICENSES.md; do
    if [ ! -f "$APP_DIR/Contents/Resources/$document" ]; then
        echo "Missing $document in the installer app resources. Rebuild with Scripts/build-app.sh and Scripts/build-installer.sh." >&2
        exit 1
    fi
done
# The archived metadata was checked above; remove only local extraction metadata.
xattr -cr "$APP_DIR"
codesign --verify --deep --strict --all-architectures "$APP_DIR"

echo "Installer checks passed: /Applications/TuneFlick.app, Universal 2, macOS requirement, payload metadata and app signature integrity."
