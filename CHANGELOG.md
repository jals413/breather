# Changelog

All notable changes to Breather. The format follows [Keep a Changelog](https://keepachangelog.com/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-10-25

### Break screen
- The clock, break name, breathing guide, buttons and hint now use the message font, so each theme reads as one typeface.

## [1.0.0] - 2026-10-25

Breather 1.0: updates itself, a guided setup and a refined set of break screens.

### Updates
- "Update Now" in Settings › About and in the notch downloads the new version, checks its SHA-256 checksum and signature, swaps it in and reopens Breather.

### Welcome
- Each setup step now uses the same header and grouped cards as Settings, and the setup asks when you count as away.

### Break screen
- Five distinct themes: Ocean Calm (aurora and ring), Forest (big digits), Paper (progress bar), Terminal (dots) and Midnight Minimal.
- Wallpapers and photos load in the background. A wallpaper in Downloads or Desktop no longer freezes the window behind macOS's folder-access prompt or leaves it hidden afterwards.

## [0.9.1] - 2026-10-25

### Welcome
- First launch is now a five-step setup: rhythm, how breaks behave, the break screen look, and the notch, menu bar and login options. Every choice is a real setting, saved as you go.

### Website
- Floating navigation, FAQ on the home page, and a full-screen break demo in the Forest look.
- New share preview image.

## [0.9.0] — 2026-10-25

First public release.

### Breaks
- Work rhythm with presets (Eye Care 20-20-20, Balanced, Deep Focus, Wellness), long breaks, office hours, planned breaks and breaks of any length.
- Skip difficulty (Casual, Balanced, Hardcore), snooze and skip-ahead limits, “End break”, optional screen lock, overtime nudge.
- Full-screen breaks on every display with eight themes, aurora backgrounds, photos, timer styles and a breathing guide.

### Smart Pause
- Waits during calls, video, fullscreen games, screen recording, chosen focus apps, and while you type.
- Time away from the Mac counts as a break, with Undo.

### Notch & menu bar
- Notch island with heads-up, final countdown, dashboard and toasts; floating pill on other displays.
- Menu bar popover with status, quick actions, pause durations and profiles.

### More
- Reminders (water, posture, blink, stand, stretch, custom), profiles that switch by app, stats with a daily Screen Score.
- Automations (Shortcuts, AppleScript, shell), `breather://` links and global shortcuts.
- iPhone and Apple Watch companions (build from source).

### Known limitations
- Not notarized: macOS asks you to approve Breather once (see the install guide).
- iPhone & Watch: Bluetooth sync has been tested in the Simulator over the local network only; Screen Time blocking and Apple push need a paid developer account and are switched off.
