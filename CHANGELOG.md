# Changelog

All notable changes to Breather. The format follows [Keep a Changelog](https://keepachangelog.com/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Updates
- "Update Now" in Settings › About and in the notch downloads the new version, checks its SHA-256 checksum and signature, swaps it in and reopens Breather.

### Welcome
- The setup now uses the same sidebar and cards as Settings, and asks when you count as away.

### Break screen
- Five distinct themes: Ocean Calm, Forest, Sunset Glow, Midnight Minimal and Paper.
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
