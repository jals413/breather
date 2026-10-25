# Breather vs LookAway (v2.4.11): feature comparison

Compiled 25 Oct 2026 from LookAway's docs, changelog, blog posts (2.2–2.4), the Mirror App Store listing, Setapp reviews and the Show HN thread.

Legend: ✅ matches · ⭐ Breather does more · 🟡 partial · ❌ missing · ➕ adopted in this pass

## Core breaks

| Feature | LookAway | Breather |
|---|---|---|
| Work interval + short break, presets | Balanced / Deep Focus / Eye Care / Wellness | ✅ same four presets |
| Long breaks every N | ✅ | ✅ |
| Skip difficulty | Casual / Balanced / Hardcore | ✅ |
| "End break" after part of the break | ✅ | ✅ adjustable % |
| Snooze +1 / +5 / +15, per-session limit | ✅ | ✅ +1 / +5, limit per break |
| Skip in advance, daily limit (−4 score each) | ✅ | ✅ (no score penalty) |
| Custom-length break ("Take a break for…") | Menu, shortcut, AppleScript | ➕ menu, shortcut and `breather://break?minutes=` |
| Keep break open until you click End Break | ✅ (2.4) | ➕ |
| Auto-lock when a break starts | ✅ | ✅ (long breaks) |
| Double-Esc to skip | ✅ | ✅ |
| Overtime nudge (worked past target) | ✅ | ➕ |
| Keep Mac awake during long breaks | ✅ | 🟡 overlay keeps display active |
| Crash or force-quit recovery | Auto-recovery | 🟡 timer state restored on relaunch; no watchdog |

## Heads-up and display

| Feature | LookAway | Breather |
|---|---|---|
| Heads-up before break (time and duration) | Floating notification | ⭐ notch island with actions; pill on other displays |
| Countdown that follows the cursor | ✅ | 🟡 countdown in the notch instead |
| Menu bar status and quick menu | ✅ | ✅ Control Center–style popover |
| Hide menu bar icon | ✅ | ✅ |
| Quick Look panel | ✅ | ✅ hover the notch for a dashboard |
| Choose which display shows alerts | ✅ (2.4) | ➕ |
| Lock Screen Live Activity on Mac | ✅ (unofficial APIs, not in their App Store build) | ❌ needs a private API; skipped |

## Smart Pause

| Feature | LookAway | Breather |
|---|---|---|
| Meetings and calls (mic or camera) with exclusions | Excludes microphones and apps | ✅ excludes apps; ignores dictation |
| Video, frontmost vs background, with exclusions | ✅ | ✅ |
| Deep-focus apps (fullscreen / foreground / open) | ✅ | ✅ |
| Fullscreen games | ✅ | ✅ (plus "any fullscreen app") |
| Screen recording and sharing | ✅ | 🟡 heuristic, debounced |
| Delay while typing, dragging or dictating | ✅ | ✅ typing and dragging; ⭐ max wait cap |
| Grace period after activity | ✅ | ✅ |
| Idle = natural break, with undo | ✅ toast + menu toggle | ✅ toast with Undo |
| Focus Filters (pause during a Focus) | ✅ | ❌ needs an Xcode project for App Intents (planned with the iPhone work) |

## Scheduling

| Feature | LookAway | Breather |
|---|---|---|
| Office hours per day, past midnight | ✅ | ✅ |
| Planned breaks (name, time, length, days, enable) | ✅ + icon, day presets | ✅ ➕ day presets |
| Planned break waits for meetings, video, focus | ✅ | ✅ waits for any Smart Pause |
| Late planned break: Start / Snooze / Skip today | ✅ | ➕ |
| Planned break suppresses nearby regular break | ✅ | ➕ |
| Apple Calendar integration | ✅ | ❌ (meeting detection covers most of it) |

## Wellbeing and stats

| Feature | LookAway | Breather |
|---|---|---|
| Posture and blink reminders | ✅ fixed set | ⭐ any number of custom reminders (water, stand, stretch…), Done / Later |
| Stats: screen time, breaks, longest / median session | ✅ | ✅ |
| App usage, website usage | ✅ incl. Firefox (Accessibility) | ✅ Safari + Chromium; ❌ Firefox |
| Screen Score 0–100 | ✅ 60 / 40 | ✅ same split |

## Customisation

| Feature | LookAway | Breather |
|---|---|---|
| Backgrounds: wallpaper, image, gradient, animated | ✅ | ⭐ + 6 aurora palettes, photo folder rotation, blur / dim |
| Timer styles, fonts, colours | ❌ | ⭐ 5 styles, 4 fonts, weights, sizes, accent |
| Themes | ❌ | ⭐ 8 themes |
| Breathing guide | ❌ | ⭐ |
| Custom messages (multi-line) | ✅ | ✅ |
| Sounds: built-in or your own, volume | ✅ | ✅ ➕ your own files; ➕ separate long-break sound (on their roadmap) |
| Profiles | ❌ | ⭐ with auto-switch by app |

## Automation and integration

| Feature | LookAway | Breather |
|---|---|---|
| Run Shortcut on start / end | ✅ | ✅ |
| Run AppleScript or shell script | ✅ | ✅ ➕ shell scripts |
| Scriptable commands | AppleScript dictionary | ✅ `breather://` URLs (Shortcuts, Raycast, Terminal) |
| Global shortcuts | ✅ several | ✅ ➕ custom break shortcut |
| iPhone / iPad mirror (Screen Time blocking, Live Activity, Watch haptic) | ✅ LookAway Mirror | ❌ next project (see below) |
| Multiple Macs, settings sync | Roadmap | ❌ |

## Platform and product

| | LookAway | Breather |
|---|---|---|
| Price | $19–$99 one-time | Personal |
| Privacy | Crash reporting (opt-out) | ⭐ no network at all |
| Languages | 7 | English only |
| Accessibility | Full (2.3) | 🟡 VoiceOver labels, Reduce Motion; needs an audit |
| macOS | 13+ | 26+ (and 27) |

## Ideas from their users that neither app has yet

- Pomodoro mode (their #2 roadmap request).
- Apple Watch haptic for breaks (comes with an iPhone Live Activity).
- Sit/stand alternation as its own schedule (our "Stand up" reminder covers the basics).
- Settings sync across Macs.

## iPhone: what it takes

LookAway Mirror pairs with a code over the internet and shows the break as a Live Activity on the Lock Screen and Dynamic Island, mirrored to Apple Watch. It also blocks apps and websites with Screen Time while the Mac is on a break. To match it, Breather needs:

1. **An iOS app.** This means moving the project to Xcode, with iOS, widget extension and Mac targets.
2. **A way to reach the phone.** Push or CloudKit works anywhere and is reliable. Local network only works while the iPhone app is awake.
3. **Screen Time (Family Controls) and push entitlements.** These need a paid Apple Developer Program membership.
