# Hard Stop — Requirements

Status: **implemented** (v0.1.0; all acceptance criteria verified live on Omarchy 4.0.0.r1758)
Target: Omarchy 4 / Quattro shell (Quickshell plugin API)
Plugin ID: `io.github.joshuaswarren.hardstop`
Kinds: `service` + `bar-widget` + `overlay`

## 1. Problem

Every timer plugin in the Omarchy marketplace points *into* work (pomodoro, deadlines, focus). None points *out*. People who hyperfocus — developers especially — don't need help starting; they need help stopping. Hard Stop is a quitting-time boundary: a countdown to the end of the workday and a short wind-down ritual that closes the day cleanly instead of letting it bleed into the evening.

## 2. Goals

- G1: Show time remaining until a user-configured stop time as a bar chip.
- G2: Escalate visibility as the stop time approaches (calm → noticeable → unmissable).
- G3: At stop time, present a fullscreen wind-down overlay: a short ritual, not a lock.
- G4: Capture a 3–5 line day recap into a plain Markdown file during wind-down.
- G5: Prompt for "tomorrow's first action" so the next morning starts without a blank page.
- G6: Support per-weekday schedules (e.g. 17:00 Mon–Fri, off Sat–Sun).
- G7: Everything theme-aware via Omarchy semantic tokens; zero hardcoded colors.

## 3. Non-goals

- NOT a screen locker or parental control. The overlay is always dismissible. This tool respects the user's agency; it creates friction, not force.
- NOT a time tracker. No analytics, no streaks, no productivity scoring. A boundary is a practice, not a grade.
- NOT a pomodoro timer. Six of those exist already.
- No cloud, no accounts, no network access at all.

## 4. UX specification

### 4.1 Bar chip (bar-widget)

| State | Trigger | Appearance |
|---|---|---|
| Idle | > `warnMinutes` before stop | Icon + `H:MM` remaining, muted foreground token |
| Warning | ≤ `warnMinutes` (default 30) | Accent-colored chip, subtle pulse once per minute |
| Final | ≤ 5 min | Chip fills with accent color, remaining minutes bold |
| After stop | Past stop time, overlay dismissed | Chip shows a small "past stop" glyph; tooltip: minutes over |
| Off-day / done | No schedule today, or ritual completed | Chip hidden (or dimmed glyph, per `showWhenIdle`) |

Interactions: left-click opens the overlay immediately (early wind-down); right-click menu: snooze 15 min (max `maxSnoozes`, default 2), skip today, open settings docs.

### 4.2 Wind-down overlay

Sequence of up to four cards, each skippable with Esc or a "not today" button:

1. **Stop card** — "That's the day." Current time, minutes worked past stop if any.
2. **Recap card** — multiline text input, 5 lines max, saved to `recapFile` as a dated Markdown section (`## 2026-08-20`). Empty input writes nothing.
3. **Tomorrow card** — single-line input: "First action tomorrow." Appended to the same file under `### Tomorrow`.
4. **Close card** — one button: "Done for today." Optional configurable shell command on completion (`onCompleteExec`, e.g. `hyprctl dispatch workspace 9` or a do-not-disturb toggle). Disabled by default.

The overlay never traps input. Esc always closes it. Reopening after dismissal is manual (chip click).

### 4.3 Notifications

Desktop notification at `warnMinutes` and at stop time (via the shell's notification path or `notify-send`). Respect a `quiet: true` setting to disable both.

## 5. Settings (inline on the `shell.json` plugin entry)

```json
{
  "id": "io.github.joshuaswarren.hardstop",
  "schedule": { "mon": "17:00", "tue": "17:00", "wed": "17:00", "thu": "17:00", "fri": "17:00" },
  "warnMinutes": 30,
  "maxSnoozes": 2,
  "recapFile": "~/Documents/day-recaps.md",
  "onCompleteExec": "",
  "quiet": false,
  "showWhenIdle": true
}
```

Defaults must produce a working plugin with zero configuration (17:00 Mon–Fri, recap file in `~/Documents`).

## 6. Architecture

- **Service**: owns the state machine (idle → warning → final → stopped → done), the clock, snooze counters, and recap-file writes. Single source of truth; bar widget and overlay read from it.
- **Bar widget**: pure presentation of service state.
- **Overlay**: `open(payloadJson)` / `close()` per the Quattro contract; payload may carry `{"early": true}` for manual invocation.
- `keepLoaded: true` — keeps the overlay mounted between summons so the wind-down opens instantly at stop time (services always stay loaded regardless; first-party overlay precedent: reminders, clipboard).
- Clock handling must survive suspend/resume (recompute from wall clock on tick, never accumulate deltas).

## 7. Security

- File writes limited to the single user-configured `recapFile` (tilde-expanded, no traversal).
- `onCompleteExec` runs a user-authored command; it is empty by default, documented as such, and never interpolates plugin data into the command string.
- No network, no credentials, no clipboard access.

## 8. Acceptance criteria

- A1: Fresh install with zero config shows a countdown chip before 17:00 on a weekday.
- A2: Chip transitions idle → warning → final at the documented thresholds (verify with a schedule set 6 min ahead).
- A3: At stop time the overlay opens once; Esc dismisses it; it does not reopen on its own.
- A4: Recap text appears in `recapFile` under today's date; file is created if missing.
- A5: Snooze delays the overlay 15 min; a third snooze is refused with a gentle message.
- A6: On a day with no schedule entry, the plugin is invisible (per `showWhenIdle: false`) and fires nothing.
- A7: Theme switch (light/dark and between themes) recolors all surfaces with no restart.
- A8: `omarchy plugin validate .` passes.
- A9: Suspend at T-40 min, resume at T-10 min → chip is in warning state within one tick.

## 9. Milestones

- M1: Service state machine + bar chip (A1, A2, A6, A9).
- M2: Overlay ritual + recap file (A3, A4, A5).
- M3: Polish — theme tokens, vertical bar support, notifications, README screenshots (A7, A8).

## 10. Open questions

- Should "skip today" persist across shell restarts? (Lean: yes, via a state file in the plugin's config dir.)
- Multi-monitor: overlay on focused monitor only, or all? (Lean: focused only.)
