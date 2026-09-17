# Calendar reminders

## Connect

Open **Settings → Calendar → Connect Calendar** and allow access when macOS asks. Focus Deck uses the calendars available in Apple Calendar. Add Google, Outlook, or iCloud accounts through **Calendar accounts…** and enable calendar sync there first.

All calendars are selected by default. Turn off **All calendars** to choose individual calendars. An empty selection shows no reminders. New calendars are included automatically only when **All calendars** is enabled.

**Disconnect** stops calendar reads and clears events from memory. To revoke the system permission too, use **System Settings → Privacy & Security → Calendars**. If permission is denied or revoked, Settings shows how to restore it. Launching Focus Deck never requests access automatically.

macOS 14+ calls reading calendar events “Full Access”; Focus Deck only reads events and never creates, edits, or deletes them. macOS 13 uses the earlier Calendar permission. Both usage descriptions are included in the app bundle. See Apple’s [Calendar access migration guide](https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels).

## Timing and display

- Lead time defaults to **10 minutes**, adjustable from **1 to 120 minutes**.
- The earliest eligible event appears above Current Focus, with its title, local start time, and a countdown updated every second.
- It is dim before the last minute. At **60 seconds remaining**, it turns white with a border.
- The reminder stays visible when hover controls fade. There are no sounds, flashing animations, or task changes.
- At the start it says **Starting now**, staying for up to 60 seconds or until the event ends, whichever comes first. It then yields to the next eligible event.
- All-day events, cancelled events, and invitations explicitly declined by the current user are skipped. Events without attendees are eligible.
- Events are refreshed every 30 seconds and when calendar data changes, the app becomes active, the system clock changes, or the Mac wakes.

## Data and tests

Calendar titles, times, and event identifiers stay in memory. Only the enabled flag, selected calendar identifiers, and lead time are saved in local preferences. No Calendar data is uploaded by Focus Deck.

`CalendarController` uses an injectable reader. Regression tests use synthetic events and a fake permission provider; they do not access real calendars or request permission. Tests cover the lead-time boundary, final-minute styling state, countdown, filtering, event transitions, connection denial/revocation, calendar selection, and settings compatibility. Synthetic previews cover dim, urgent, and starting states at two sizes.

Run `./scripts/test.sh`. Native permission dialogs and account synchronization still require a manual check with the installed signed app.
