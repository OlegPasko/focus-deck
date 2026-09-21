# Focus Deck

**One task. A quieter screen.** A native Mac app that keeps your current task in large, readable text over a calm landscape. Put it on a second screen, keep it above other windows, and get back to work.

![Focus Deck with an example task](docs/previews/v2/deck-wide.png)

## Download

[Download Focus Deck for macOS](https://share.everlabs.net/share/d7d12f75/index.html) · **Version 1.4.0** · macOS 13+ · Apple silicon and Intel

The downloadable preview is ad-hoc signed and **not notarized**. If macOS blocks it, follow the download page's installation instructions. Updates are installed manually.

[What’s new](CHANGELOG.md)

## Features

- **One task at a time:** large text, a resizable window, remembered position, and an optional “Foreground of all windows” setting.
- **Todoist Today:** create a task due today, select existing tasks, and complete the linked task from the app. “Later” shows the next task for today. When none remain, it shows “No more tasks for today.”
- **Upcoming meetings:** connect Apple Calendar in Settings, choose calendars, and set a lead time (10 minutes by default). A live countdown appears above Current Focus, dim until the final minute, then white with a border.
- **Quiet backgrounds:** six landscapes, with one stable image per task in Gallery or a fixed wallpaper of your choice. No timed slideshow. Plain midnight and classic animated synthwave are also available.
- **Spotify controls:** a dimmed 60 × 60 album-cover square with play/pause and quiet playback bars. Hover for the track, artist, and a next-track button in the upper-right of the translucent menu.
- **Low-distraction controls:** controls and the Everlabs link fade together; macOS Reduce Motion is respected.
- **CLI integration:** scripts and agents can set a focus task, manage the local queue, or display a temporary message.

## Get started

1. Download the disk image and drag **Focus Deck** into **Applications**.
2. Open Settings with **⌘,**. To connect Todoist, copy your token from [Todoist Settings → Integrations → Developer](https://app.todoist.com/app/settings/integrations) and save it in Focus Deck.
3. Press **⌘E** to capture a task for Today: **Just add to Today** keeps your focus, **Add to Today & make next** selects it as your next task in Focus Deck, and **Add to Today & focus** switches immediately. Use **⌘K** to choose an existing task.
4. Press **⌘D** to complete it. With Todoist connected, Focus Deck moves to the next task for today.
5. For music, open the Spotify desktop app and allow Focus Deck to control it when macOS asks.

For meeting reminders, open **Settings → Calendar → Connect Calendar**, allow calendar access, then choose all calendars or a specific selection. Google and Outlook accounts must first be connected to Apple Calendar through macOS Internet Accounts. The lead time can be set from 1 to 120 minutes. See [Calendar reminders](docs/calendar.md).

Spotify controls address the desktop app directly. Browser-only playback is not supported. The task picker can include overdue tasks; the separate **Later** list uses only tasks due today.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Create or edit focus | ⌘E |
| Choose a Todoist task | ⌘K |
| Complete current task | ⌘D |
| Refresh Todoist | ⌘R |
| Increase / decrease text size | ⌘+ / ⌘− |
| Move to the next display | ⌃⌥→ |
| Fill the current display | ⇧⌘F |
| Full screen | ⌃⌘F |
| Settings | ⌘, |

The **Focus** menu includes the always-on-top setting and window positioning controls. Hover to reveal the deck controls; double-click the task title to edit it.

## Your data

- Your Todoist API token is stored in the macOS Keychain. **Disconnect** removes it.
- Task titles, history, and preferences stay in `~/Library/Application Support/FocusDeck/` as local JSON files. Treat these files as personal data.
- The app contacts Todoist for task operations and sync, and downloads artwork from the URL supplied by Spotify. Playback control uses local macOS Automation.
- Calendar events are read locally through macOS and kept in memory, not copied to the app’s state files or sent to a server. Calendar selection and lead time are saved in local preferences. Disconnect stops reading calendars.
- The Everlabs logo opens [everlabs.com](https://everlabs.com) only when clicked.
- Downloads contain the app and its bundled artwork, without the publisher's tasks, settings, or credentials.

## Build from source

Install Xcode with its command-line tools, then:

```bash
git clone https://github.com/OlegPasko/focus-deck.git
cd focus-deck
./scripts/test.sh
./scripts/build_app.sh release
open "dist/Focus Deck.app"
```

New clones use ad-hoc signing. To keep local Keychain permissions stable across builds, set your certificate with `git config --local focusdeck.signingIdentity YOUR_CERTIFICATE_SHA1`. This configuration stays local. `./scripts/install_desktop.sh` optionally installs to `~/Applications`, adds a Desktop alias, and copies the CLI to `~/.local/bin`.

The SwiftUI app lives in `Sources/FocusDeck`, shared models and services in `Sources/FocusDeckKit`, and the CLI in `Sources/focusdeck-cli`. Tests cover state locking, Todoist requests and advancement, artwork, title layout, and rendered views. They use temporary state and stubbed API responses.

## Scripts and agents

```bash
focusdeck set "Write the release notes" --project "Example"
focusdeck overlay "Build finished" --kind agent --ttl 15
focusdeck queue "Review changes" "Update documentation"
focusdeck done
focusdeck status --json
```

The CLI's `done` command advances its local queue. The app handles Todoist completion and Today advancement. Set `FOCUSDECK_HOME` to a temporary directory for isolated manual checks.

## Documentation

- [Todoist integration](docs/todoist.md)
- [Calendar reminders](docs/calendar.md)
- [CLI and shared-state integration](docs/agent-integration.md)
- [Wallpapers and generation prompts](docs/omarchy-wallpapers.md)

The original wallpapers are inspired by dark terminal palettes and [Omarchy](https://omarchy.org/). Focus Deck is an independent project and is not affiliated with Spotify, Todoist, or Omarchy.
