# LookAway clone — spec (personal, macOS only)

Working name: **Breather** (bundle id `com.jalthakor.breather`).

Target: macOS 26 (Tahoe) and macOS 27. Native Swift + SwiftUI/AppKit, built with Xcode 26.6.
- Deployment target is macOS 26.0. The macOS 26 SDK binary runs unchanged on 27.
- Nothing relies on private APIs or exact window-server layouts, so a 27 upgrade shouldn't break it.
- macOS 27-only APIs get added behind `if #available(macOS 27, *)` once Xcode 27 is installed.

Not sandboxed, not App Store, so it can use CGEvent, IOKit and CoreAudio freely. Ad-hoc signed.
Phase 1 needs **no** privacy permissions: idle and typing come from CGEventSource; mic and camera "in use" come from CoreAudio and CoreMediaIO; windows from CGWindowList bounds only; video from IOKit power assertions; hotkeys from Carbon.

## Notch design (signature feature)
On a MacBook Pro with a notch, the notch is the app's home, Dynamic Island style. A black shape grows out of the hardware notch, so the two blend into one.
- **Resting:** invisible. Optional "live activity" mode: a progress ring on the left of the notch and the time to next break on the right, both tucked into the menu bar.
- **Hover:** it expands to show status (next break, today's breaks, pause reason) with quick actions: break now, pause, skip next.
- **Heads-up:** a minute before a break it widens to "Break in 0:58" with Start now / +1m / +5m / Skip. It never steals keyboard focus.
- **Final countdown:** 5…1 in the notch, then the full-screen break fades in.
- **Toasts:** "Away 7 min, counted as a break · Undo", "Paused: in a meeting", "Resumed".
- **Without a notch** (external display or lid closed): the same UI as a floating pill dropping from the top centre.
- Spring animations; respects Reduce Motion.

## What LookAway does today (v2.4.11)

**Breaks**
- Work interval plus short break (presets: Balanced, Deep Focus, Eye Care, Wellness). Long break every N short breaks.
- Full-screen break overlay on all displays: countdown, message, background (wallpaper, blur, gradient, image, animated), sound.
- Skip difficulty: Casual (skip anytime), Balanced (skip unlocks after a few seconds), Hardcore (no skip).
- Snooze +1m / +5m / +15m, with per-session and daily postpone limits. Double-Esc to skip. "End Break" replaces Skip once enough time has passed.
- Start a break now, skip the next break in advance (daily limit), break on demand with a custom length.
- Optional auto-lock when a break starts. Keeps the Mac awake during long breaks.
- Option to keep the break open until you click End Break.

**Heads-up**
- Notice before a break (default 1 min ahead, shown for 10 s), with snooze. Compact style, choice of position and display.
- Floating 5 s / 10 s countdown that follows the cursor.
- Overtime nudge when you've worked past the planned screen time.

**Smart Pause**
- Meetings and calls, detected from mic/camera, with excluded mics and apps.
- Video playback, frontmost only or in the background, with excluded apps.
- Deep-focus apps: pause when foreground and fullscreen, when foreground, or whenever open.
- Fullscreen games. Screen recording and sharing.
- Typing, dragging and dictation postpone a break until you stop.
- Configurable delay after an activity ends (1, 2 or 5 min).
- Idle handling: time away counts as a natural break, with an undo toast and an away-time review.

**Scheduling**
- Office hours per weekday, including past midnight.
- Planned breaks at fixed times (lunch, a walk) that respect meetings. Missed ones are marked "ignored".
- Apple Calendar integration.

**Wellness**
- Posture and blink reminders (subtle animations), configurable.

**Stats**
- Screen time, break count, longest session, median session.
- Per-app usage, plus per-website usage (Safari, Chromium and Firefox browsers).
- Screen Score from 0 to 100: session discipline (60) plus break adherence (40).

**Mac integration**
- Menu bar icon with live status. The icon can be hidden. Quick Look panel.
- Global keyboard shortcuts. Focus Filters, and start/stop based on Focus.
- AppleScript commands. Automations that run a Shortcut or AppleScript when a break starts or ends.
- Lock Screen Live Activity. Light/dark appearance. Accessibility support (VoiceOver, reduced motion).
- Recovers after crashes. Launch at login.

**Out of scope (Mac only, personal use):** iPhone/iPad Mirror sync, licensing, localization.

## What users complain about

| Complaint | Source | How we handle it |
|---|---|---|
| Asks for a break when you've just been away | Setapp reviews | Idle handling on by default: time away counts as a break and resets the timer |
| Interrupts deep focus or writing mid-sentence | HN, Setapp | Wait for a typing pause, with a grace window; a "writing" heuristic; the notice never steals focus |
| Fixed intervals, "no sensible detection" | Setapp | Flexible break window (e.g. 18–25 min): fire at the first natural lull |
| Startling default sound | HN | Soft default sound with a volume control, or no sound |
| Blink reminder feels pointless | Setapp | Every wellness reminder is opt-in and toggled separately |
| High RAM (~150 MB) and CPU spikes | Setapp, HN, changelog | Event-driven, no polling loops; goal under 40 MB idle |
| Breaks behind fullscreen apps; multi-display bugs | Changelog | Overlay windows at screen-saver level on every NSScreen; rebuild them when the display setup changes |
| Timer wrong after sleep or unlock; negative countdown | Changelog | Wall-clock based timer that handles sleep, wake and lock events |
| Disabled it and forgot to turn it back on | HN | Every pause has a duration (30 m, 1 h, until tomorrow, indefinite) and reminds you before it ends |
| Accidental consent clicks | HN | No telemetry at all |

## Extras we're adding
- **Custom reminders:** water, stretch, sit/stand, eye drops. Each has its own interval, style (notice or overlay), sound and office hours.
- **Smarter interruption rules:** see the table above.
- **Profiles:** saved setting sets such as Coding or Writing. Switch from the menu bar, or automatically by Focus mode or the frontmost app.

## Phases
1. **Core:** menu bar, settings window, timer engine, break overlay on all displays, heads-up notice, snooze/skip and difficulty, idle handling, Smart Pause (meetings, video, fullscreen, screen share, typing, focus apps), office hours, global shortcuts, launch at login.
2. **Polish:** stats with apps, sites and Screen Score; wellness and custom reminders; profiles; planned breaks; themes and sounds; automations and AppleScript; Focus filters; Calendar.
