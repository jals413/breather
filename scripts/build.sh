#!/bin/zsh
# Builds Breather.app into ./build and (optionally) installs it to /Applications.
# Usage: scripts/build.sh [--install] [--run]
#
# Environment:
#   BREATHER_PAID=1     compile in paid developer-program features (Apple push to iPhone)
#   UNIVERSAL=1         build for Apple silicon and Intel (releases do this)
#   VERSION=1.2.3       stamp the version (defaults to the one in Resources/Info.plist)
#   SIGN_IDENTITY=-     force ad-hoc signing (releases do this)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
APP=build/Breather.app
ARCHS=(--arch arm64)
[[ "${UNIVERSAL:-0}" == 1 ]] && ARCHS=(--arch arm64 --arch x86_64)

swift build -c "$CONFIG" "${ARCHS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)/Breather"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Breather"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$APP/Contents/Info.plist"
fi

# A stable signing identity lets macOS remember Bluetooth / local network / automation
# permissions across rebuilds. Ad hoc ("-") works too, but macOS asks again after every build.
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}
[[ "$IDENTITY" == "-" ]] && IDENTITY=""
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad hoc})"
if [[ -z "$IDENTITY" ]]; then
  echo "Tip: add your Apple ID in Xcode > Settings > Accounts so macOS stops re-asking for permissions after each build."
fi

for arg in "$@"; do
  case "$arg" in
    --install)
      pkill -f "Breather.app/Contents/MacOS/Breather" 2>/dev/null || true  # not the iOS Simulator copies
      rm -rf /Applications/Breather.app
      cp -R "$APP" /Applications/
      APP=/Applications/Breather.app
      echo "Installed to $APP"
      ;;
    --run)
      pkill -f "Breather.app/Contents/MacOS/Breather" 2>/dev/null || true  # not the iOS Simulator copies
      open "$APP"
      ;;
  esac
done
