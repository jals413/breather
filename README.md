<p align="center"><img src="Resources/Branding/AppIcon-1024.png" width="128" alt="Breather icon"></p>

<h1 align="center">Breather</h1>
<p align="center"><b>Rest your eyes. Keep your flow.</b><br>Break reminders that live in your MacBook's notch — free and open source.</p>

<p align="center">
  <a href="https://jals413.github.io/breather/">Website</a> ·
  <a href="https://github.com/jals413/breather/releases/latest">Download</a> ·
  <a href="https://jals413.github.io/breather/install.html">Install guide</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

---

Breather reminds you to look away from the screen (20-20-20 by default) without wrecking your focus. A heads-up grows out of the notch before each break, the break fills every display, and it waits politely while you're in a call, watching something, presenting, or mid-sentence. Time spent away from your Mac counts as a break. Nothing ever leaves your Mac.

## Install

Breather needs **macOS 26 Tahoe or later** (macOS 27 included) on Apple silicon or Intel.

**Homebrew**

```bash
brew install --cask jals413/tap/breather
```

**One-line install**

```bash
curl -fsSL https://jals413.github.io/breather/install.sh | bash
```

**Download** — grab `Breather-x.y.z.dmg` from the [latest release](https://github.com/jals413/breather/releases/latest), open it and drag Breather to Applications.

**From source** — see [Build from source](#build-from-source).

### First launch: “Breather can't be opened”

Breather is free and open source, and isn't notarized by Apple (that needs a paid developer membership). macOS therefore asks you to approve it once. Homebrew and the one-line installer do this for you; if you downloaded the DMG:

1. Open Breather. macOS says it can't verify the developer — click **Done**.
2. Open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to Breather.
3. Confirm with **Open Anyway** and your password. That's it — macOS remembers the choice.

Prefer Terminal? This does the same thing:

```bash
xattr -dr com.apple.quarantine /Applications/Breather.app
```

Every release is built by [GitHub Actions](.github/workflows/release.yml) from the tagged source, and its SHA-256 checksums are published with it, so you can check what you're running.

## Features

- **Notch island.** Heads-ups grow out of the hardware notch, Dynamic Island–style, with Start now / +1 min / +5 min / Skip. Hover the notch for a quick dashboard. Displays without a notch get a floating pill.
- **Full-screen breaks on every display** with eight themes, animated aurora backgrounds, your own photos, five timer styles, fonts, colours and a breathing guide.
- **Smart Pause.** Breaks wait during calls (any app using the mic or camera), video, fullscreen games, screen recording and focus apps you choose — and until you stop typing.
- **Time away counts.** Step away and that time is a break, with Undo.
- **Skip difficulty** from Casual to Hardcore, snooze limits, skip-ahead limits, “End break” after part of the break.
- **Schedule.** Long breaks, office hours, planned breaks (lunch!), and breaks of any length on demand.
- **Reminders** to drink water, fix posture, blink, stand or stretch — counted on active screen time only.
- **Profiles** (Everyday, Deep Work, Gentle…) that switch automatically by app.
- **Stats.** A daily Screen Score, screen time, longest stretch, a seven-day view, top apps and (opt-in) websites.
- **Automations.** Run Shortcuts, AppleScript or shell scripts when breaks start and end; control Breather with `breather://` links and global keyboard shortcuts.
- **iPhone & Apple Watch** companions *(build from source for now)* — breaks on the Lock Screen and Dynamic Island, a tap on your wrist, stats on your phone.

## Privacy

No account, no analytics, no tracking. Breather's only network activity is a once-a-day check for new versions on GitHub (you can turn it off), and talking to your own paired iPhone. Stats live in `~/Library/Application Support/Breather` and never leave your Mac. The core needs no privacy permissions; website stats are opt-in and macOS asks once per browser.

## iPhone & Apple Watch

The companion apps live in [`Apps/`](Apps) and are built with Xcode. Apple doesn't allow sharing iPhone apps outside the App Store without a paid developer account, so for now you build them yourself — a free Apple ID works:

```bash
scripts/mobile.sh device <YOUR_TEAM_ID>   # installs on your connected iPhone (and its Watch)
```

Apps installed with a free Apple ID need reinstalling every 7 days. Blocking apps on your iPhone during breaks (Screen Time) and Apple push are built in but switched off until the project has a paid developer account.

## Build from source

Requirements: macOS 26+, Xcode 26+.

```bash
git clone https://github.com/jals413/breather.git
cd breather
scripts/build.sh --install --run   # builds Breather.app, copies it to /Applications, launches it
swift test                         # engine, scheduling, link and push-payload tests
```

| Command | What it does |
|---|---|
| `scripts/build.sh` | Builds `build/Breather.app` (`--install`, `--run`) |
| `scripts/release.sh 1.2.3` | Universal release zip + DMG + checksums in `dist/` |
| `scripts/mobile.sh sim` | Builds and runs the iPhone + Watch apps in the Simulator |
| `xcodegen generate` | Regenerates `BreatherMobile.xcodeproj` from `project.yml` |

Developer tools built into the app:

```bash
B=build/Breather.app/Contents/MacOS/Breather
$B --diagnose                  # what every Smart Pause detector sees right now
$B --render-snapshots <dir>    # PNGs of the notch, popover, themes and welcome screen
$B --animation-test <dir>      # frame-by-frame recording of every notch transition
```

### Project layout

| Path | What's there |
|---|---|
| `Sources/Breather` | The Mac app: engine, detectors, notch, break screen, settings |
| `Sources/BreatherKit` | Shared with iPhone & Watch: link protocol, design system, Live Activity model |
| `Apps/` | iPhone app, Live Activity, notification extension, Watch app and complications |
| `Tests/` | Engine, routines, link and push-payload tests |
| `website/` | The project website (GitHub Pages) |
| `packaging/` | Homebrew cask template |

## Contributing

Bug reports, ideas and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

Breather is free software, released under the [GNU General Public License v3.0](LICENSE). You can use, study, share and change it; if you distribute a modified version, it must be under the same licence.

Copyright © 2026 Jal Thakor.
