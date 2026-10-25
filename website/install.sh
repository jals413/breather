#!/bin/bash
# Installs the latest Breather: curl -fsSL https://jals413.github.io/breather/install.sh | bash
#
# What it does: downloads the latest release from GitHub, checks its SHA-256 against the
# published checksums, installs it to /Applications (or ~/Applications), clears the download
# quarantine so macOS opens it without the "can't be verified" prompt, and launches it.
set -euo pipefail

REPO="jals413/breather"
BASE="https://github.com/$REPO/releases/latest/download"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Breather is a Mac app."
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 26 )) || die "Breather needs macOS 26 Tahoe or later (you have $(sw_vers -productVersion))."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say "Downloading the latest Breather…"
curl -fsSL "$BASE/Breather.zip" -o "$tmp/Breather.zip" || die "Download failed."
curl -fsSL "$BASE/checksums.txt" -o "$tmp/checksums.txt" || die "Couldn't fetch checksums."

expected=$(awk '$2 == "Breather.zip" {print $1}' "$tmp/checksums.txt")
actual=$(shasum -a 256 "$tmp/Breather.zip" | awk '{print $1}')
[[ -n "$expected" && "$expected" == "$actual" ]] || die "Checksum mismatch, so not installing."
say "Checksum verified."

# BREATHER_DEST overrides where it installs (used for testing).
dest="${BREATHER_DEST:-/Applications}"
[[ -w "$dest" ]] || { dest="$HOME/Applications"; mkdir -p "$dest"; }

[[ -z "${BREATHER_DEST:-}" ]] && { pkill -f "Breather.app/Contents/MacOS/Breather" 2>/dev/null || true; }
rm -rf "$dest/Breather.app"
ditto -x -k "$tmp/Breather.zip" "$dest"
xattr -dr com.apple.quarantine "$dest/Breather.app" 2>/dev/null || true

say "Installed to $dest/Breather.app"
if [[ -z "${BREATHER_NO_OPEN:-}" ]]; then
  open "$dest/Breather.app"
  say "Breather is running. Look for it in your menu bar and notch."
fi
