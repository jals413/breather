#!/bin/zsh
# Renders the Homebrew cask for a release: scripts/update-cask.sh 0.9.0 <path/to/tap>/Casks/breather.rb
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?version}; VERSION=${VERSION#v}
OUT=${2:-dist/breather.rb}
SHA=$(awk -v f="Breather-$VERSION.zip" '$2 == f {print $1}' dist/checksums.txt)
[[ -n "$SHA" ]] || { echo "No checksum for Breather-$VERSION.zip in dist/checksums.txt" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" packaging/homebrew/breather.rb.template > "$OUT"
echo "Wrote $OUT"
