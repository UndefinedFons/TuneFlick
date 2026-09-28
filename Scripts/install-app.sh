#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_APP="$PROJECT_DIR/build/TuneFlick.app"
USER_APPLICATIONS_DIR="$HOME/Applications"
INSTALLED_APP="$USER_APPLICATIONS_DIR/TuneFlick.app"
DESIGNATED_REQUIREMENT='=designated => identifier "com.tuneflick.app"'

"$PROJECT_DIR/Scripts/build-app.sh"
mkdir -p "$USER_APPLICATIONS_DIR"

if [ -e "$INSTALLED_APP" ]; then
    rm -rf "$INSTALLED_APP"
fi

ditto --noextattr --norsrc "$BUILD_APP" "$INSTALLED_APP"
xattr -cr "$INSTALLED_APP"
codesign --force --sign - --requirements "$DESIGNATED_REQUIREMENT" "$INSTALLED_APP" >/dev/null
codesign --verify --deep --strict "$INSTALLED_APP"

echo "Installed $INSTALLED_APP"
