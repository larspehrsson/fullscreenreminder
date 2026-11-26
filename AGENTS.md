# Agent Context — FullscreenReminder

macOS menu bar app (Swift/SwiftUI) that shows full-screen reminders for upcoming calendar events. Uses EventKit to fetch events.

## Key source files

| File                         | Purpose                                                                         |
| ---------------------------- | ------------------------------------------------------------------------------- |
| `FullscreenReminder.swift`   | `AppDelegate` — event fetching, timer scheduling, status bar, reminder dispatch |
| `ReminderOccurrenceID.swift` | Stable identity for a specific occurrence of a recurring event                  |
| `ReminderView.swift`         | Full-screen reminder window UI                                                  |
| `MeetingsView.swift`         | Popover list of upcoming meetings                                               |
| `MeetingsViewModel.swift`    | View model; builds `MeetingRow` / `MeetingSection` from `EKEvent`               |
| `ReminderPreferences.swift`  | UserDefaults-backed settings                                                    |
| `AppUpdater.swift`           | Sparkle in-app updates (feed + public key in `Info.plist`, appcast built in CI) |
| `SettingsWindowController.swift` | AppKit settings window (the app has no SwiftUI `App`/`Settings` scene)     |

## Architecture notes

- Events are fetched on `eventStoreQueue` (background) then dispatched to main for all state mutations.
- `ReminderOccurrenceID` is the key type used across `reminderTimers`, `reminderEvents`, `triggeredReminderLeadTimes`, and `snoozeTimers`. It pairs `eventIdentifier` with `occurrenceStart` (= `event.startDate`) so each occurrence of a recurring series has a distinct key.
- `reminderEvents[occurrenceID]` caches the `EKEvent` object for each scheduled occurrence. This is the preferred lookup when a timer fires. The fallback chain is: `reminderEvents` → search `upcomingEvents` by identifier + start date → `eventStore.event(withIdentifier:)` (last resort; may return wrong occurrence for recurring events).
- `AppDelegate.upcomingEvents` is the current list of fetched `EKEvent` objects, refreshed every minute and on EventKit change notifications.

## Known/fixed bug — recurring meeting shows wrong time in popup

**Symptom:** Reminder popup fires at the correct time but displays a time far in the future (e.g. "Starts in 336h 15m" when the meeting is actually 15 minutes away).

**Root cause:** Two issues working together:
1. `ReminderOccurrenceID.occurrenceStart` was computed as `event.occurrenceDate ?? event.startDate`. For recurring events, `occurrenceDate` can be inconsistent across EventKit fetches, causing the stored key to not match the key used at timer fire time, so `reminderEvents[occurrenceID]` returns nil.
2. The fallback `eventStore.event(withIdentifier:)` returns an arbitrary occurrence of the recurring series — often the next one (e.g. 14 days away for a bi-weekly meeting) rather than the current one.

**Fix applied:**
- `ReminderOccurrenceID` now always uses `event.startDate` (stable, unique per occurrence).
- Both fallback sites (`handleScheduledReminder` and the snooze timer handler) now search `upcomingEvents` for an occurrence matching `eventIdentifier` + `startDate` within 60 s before falling through to `eventStore.event(withIdentifier:)`.

## Build & deploy

```shell
./build.sh
killall FullscreenReminder
cp -r "dist/FullscreenReminder.app" /Applications
open "/Applications/FullscreenReminder.app"
```

For CI releases (GitHub Actions: `latest` pre-release from `main`, versioned releases from `v*` tags) see `README.md`.
