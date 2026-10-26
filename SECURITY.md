# Security

Please report security problems privately via [GitHub's private vulnerability reporting](https://github.com/jals413/breather/security/advisories/new) rather than in a public issue. You'll get a reply within a few days.

## What Breather does and doesn't do

- **Network:** a daily request to the GitHub Releases API to check for updates (can be turned off), and connections to your own paired iPhone over Bluetooth or your local network. No analytics, no tracking.
- **iPhone link:** pairing uses the 6-digit code (or the QR code's longer key) shown on your Mac. The phone and Mac agree on a key with an X25519 key exchange tied to the code. The key never crosses the air, and a fake phone or fake Mac can't test guesses of the code. Each code allows one attempt and expires after two minutes. Each phone gets its own key, every message is encrypted (ChaCha20-Poly1305) and counted so it can't be replayed, and the Mac sends nothing to a connection until a paired phone proves itself on it. Forgetting a phone deletes its key.
- **`breather://` links:** any app or web page can open them, so break, snooze and pause lengths from links (and from the phone) are capped, and `breather://pair` only opens Settings.
- **Data:** settings in `~/Library/Preferences/com.jalthakor.breather.plist`; stats and the phones' link keys in `~/Library/Application Support/Breather` (the key file is readable only by your user).
- **Signing:** releases are ad-hoc signed and built in public by GitHub Actions; each release lists SHA-256 checksums.
