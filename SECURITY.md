# Security

Please report security problems privately via [GitHub's private vulnerability reporting](https://github.com/jals413/breather/security/advisories/new) rather than in a public issue. You'll get a reply within a few days.

## What Breather does and doesn't do

- **Network:** a daily request to the GitHub Releases API to check for updates (can be turned off), and connections to your own paired iPhone over Bluetooth or your local network. No analytics, no tracking.
- **iPhone link:** pairing uses a 6-digit code shown on your Mac; every message after that is signed (HMAC-SHA256) with a secret only your Mac and phone share.
- **Data:** settings in `~/Library/Preferences/com.jalthakor.breather.plist`; stats and the link secret in `~/Library/Application Support/Breather` (the secret file is readable only by your user).
- **Signing:** releases are ad-hoc signed and built in public by GitHub Actions; each release lists SHA-256 checksums.
