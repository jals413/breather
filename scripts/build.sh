#!/bin/zsh
# Builds Breather.app into ./build and (optionally) installs it to /Applications.
# Usage: scripts/build.sh [--install] [--run]
# Paid developer-program features (Apple push to iPhone): BREATHER_PAID=1 scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
APP=build/Breather.app

swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Breather"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Breather"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --deep --sign - "$APP"
echo "Built $APP"

for arg in "$@"; do
  case "$arg" in
    --install)
      pkill -x Breather 2>/dev/null || true
      rm -rf /Applications/Breather.app
      cp -R "$APP" /Applications/
      APP=/Applications/Breather.app
      echo "Installed to $APP"
      ;;
    --run)
      pkill -x Breather 2>/dev/null || true
      open "$APP"
      ;;
  esac
done
