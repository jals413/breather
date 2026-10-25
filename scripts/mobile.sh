#!/bin/zsh
# Builds the iPhone + Apple Watch apps.
#   scripts/mobile.sh sim            build and run in the iOS Simulator (no account needed)
#   scripts/mobile.sh device TEAMID  build and install on your connected iPhone (free or paid Apple ID)
#   PAID=1 scripts/mobile.sh ...     use the Paid configuration (push + Screen Time)
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
CONFIG=${PAID:+DebugPaid}
CONFIG=${CONFIG:-Debug}

case "${1:-sim}" in
  sim)
    DEVICE=$(xcrun simctl list devices available | grep -m1 -E "iPhone 1[6-9] Pro" | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    open -a Simulator
    xcodebuild -project BreatherMobile.xcodeproj -scheme BreatherPhone -configuration "$CONFIG" \
      -destination "id=$DEVICE" -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build | grep -E "error:|\*\* BUILD"
    APP=.build/xcode/Build/Products/$CONFIG-iphonesimulator/Breather.app
    xcrun simctl install "$DEVICE" "$APP"
    xcrun simctl launch "$DEVICE" com.jalthakor.breather.ios
    ;;
  device)
    TEAM=${2:?"Pass your Team ID (Xcode → Settings → Accounts)"}
    xcodebuild -project BreatherMobile.xcodeproj -scheme BreatherPhone -configuration "$CONFIG" \
      -destination "generic/platform=iOS" -derivedDataPath .build/xcode -allowProvisioningUpdates \
      DEVELOPMENT_TEAM="$TEAM" build | grep -E "error:|\*\* BUILD"
    APP=.build/xcode/Build/Products/$CONFIG-iphoneos/Breather.app
    PHONE=$(xcrun devicectl list devices | awk '/iPhone/ && /connected|available/ {print $3; exit}')
    xcrun devicectl device install app --device "$PHONE" "$APP"
    ;;
esac
