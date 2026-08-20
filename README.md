# Hard Stop

A quitting-time boundary for the [Omarchy](https://omarchy.org) bar. Every other timer points into work — this one points out.

Hard Stop counts down to the end of your workday, escalates gently as the boundary approaches, and closes the day with a short wind-down ritual: a five-line recap, tomorrow's first action, done. No lock, no scorecard, no cloud.

> **Status: specification phase.** The plugin contract, UX, and acceptance criteria are fully defined in [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md). Implementation has not started. Watch the repo if you want the working version.

## Planned features

- Countdown chip in the bar with calm → warning → final escalation
- Per-weekday stop times (default 17:00 Mon–Fri)
- Fullscreen wind-down overlay: day recap + tomorrow's first action, saved to plain Markdown
- Snooze (bounded), skip-today, and an always-available Esc — friction, not force
- Theme-aware via Omarchy semantic tokens; horizontal and vertical bars
- Zero network access, zero accounts, zero analytics

## Plugin contract

- **ID:** `io.github.joshuaswarren.hardstop`
- **Kinds:** `service` + `bar-widget` + `overlay`
- **Compatibility target:** Omarchy 4 / Quattro shell

## Installation (once implemented)

```bash
omarchy plugin add https://github.com/joshuaswarren/omarchy-hardstop
```

## Configuration

Settings live inline on the plugin entry in `~/.config/omarchy/shell.json` — see [docs/REQUIREMENTS.md §5](docs/REQUIREMENTS.md#5-settings-inline-on-the-shelljson-plugin-entry) for the full schema and defaults.

## Security

Hard Stop writes to one user-configured Markdown file and nothing else. The optional `onCompleteExec` hook runs a command you author yourself and ships empty. No network, credentials, or clipboard access.

## License

[MIT](LICENSE)
