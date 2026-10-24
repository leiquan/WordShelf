#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/opt/homebrew/bin
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/date-group-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --scratch-path .build/date-group -c debug --arch arm64 --disable-sandbox --cache-path .build/cache
BIN_DIR="$(swift build --scratch-path .build/date-group -c debug --arch arm64 --show-bin-path --disable-sandbox --cache-path .build/cache)"
APP="$PWD/dist/WordShelf.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/WordShelf" "$APP/Contents/MacOS/WordShelf"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Include package resources as well, so both app-bundle and package launch paths work.
if [ -d "$BIN_DIR/WordShelf_WordShelf.bundle" ]; then
  ditto "$BIN_DIR/WordShelf_WordShelf.bundle" "$APP/Contents/Resources/WordShelf_WordShelf.bundle"
fi
# Set WORDSHELF_SIGNING_IDENTITY to an existing Apple Development / Developer ID
# certificate fingerprint for a stable identity across updates. Never weaken requirements.
SIGNING_IDENTITY="${WORDSHELF_SIGNING_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
if [ "$SIGNING_IDENTITY" = "-" ]; then
  echo "Local ad-hoc build: after an update, remove the old Accessibility entry and authorize this app again."
fi
echo "$APP"
