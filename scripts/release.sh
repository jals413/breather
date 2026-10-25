#!/bin/zsh
# Builds a release: a universal, ad-hoc-signed Breather.app packaged as a zip and a DMG,
# with SHA-256 checksums. Output goes to ./dist.
#
#   scripts/release.sh 0.9.0
#
# Breather isn't notarized (that needs a paid Apple Developer account), so macOS asks users
# to approve it once. See website/install.html and the README.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?"usage: scripts/release.sh <version>, e.g. 0.9.0"}
VERSION=${VERSION#v}

UNIVERSAL=1 VERSION="$VERSION" SIGN_IDENTITY=- scripts/build.sh
codesign --verify --deep --strict build/Breather.app
lipo -info build/Breather.app/Contents/MacOS/Breather

rm -rf dist && mkdir -p dist
ZIP="dist/Breather-$VERSION.zip"
DMG="dist/Breather-$VERSION.dmg"

# Zip: what Homebrew and the install script use.
ditto -c -k --sequesterRsrc --keepParent build/Breather.app "$ZIP"

# DMG: drag Breather onto Applications.
STAGE=$(mktemp -d)
cp -R build/Breather.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Breather $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"

# Stable names too, so https://github.com/<repo>/releases/latest/download/Breather.dmg always works.
cp "$ZIP" dist/Breather.zip
cp "$DMG" dist/Breather.dmg

(cd dist && shasum -a 256 Breather-"$VERSION".zip Breather-"$VERSION".dmg Breather.zip Breather.dmg > checksums.txt)
cat dist/checksums.txt
echo "Release $VERSION ready in dist/"
