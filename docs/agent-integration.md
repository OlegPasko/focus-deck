# Putting the deck under agent control

The deck is a display for **one** task. Any process can change that task.

## The shared file

`~/Library/Application Support/FocusDeck/focus.json`

```json
{
  "revision": 12,
  "writer": "cli",
  "updatedAt": "2026-09-15T09:12:44Z",
  "current": {
    "id": "6F3C…",
    "title": "Ship the visuals engine",
    "source": "agent",
    "project": "focus-deck",
    "detail": null,
    "startedAt": "2026-09-15T09:05:00Z",
    "coverSeed": 12345678901234
  },
  "queue": [ { "id": "…", "title": "Write the changelog", "source": "custom", "coverSeed": 99 } ],
  "history": [],
  "overlay": null
}
```

Rules:

- Always **increase `revision`** and set `updatedAt`. The app adopts the file whenever its
  content differs from what it has in memory, so an equal revision is not enough to hide a change.
- Set `writer` to something you recognise (`cli`, `agent`, your tool name).
- Write the file atomically (write a temp file, then rename).
- `coverSeed` is optional: the app derives one from the title when it is missing (`FNV-1a` of the
  trimmed, lower-cased title). Set it yourself to choose the artwork.

## Several writers at once

The app, the CLI and your agents may all write. Two protections exist:

- **File lock.** `focusdeck` and the app take an exclusive lock (`focus.json.lock`) around a
  read-modify-write cycle, so their changes merge instead of overwriting each other. Verified:
  8 processes doing 10 writes each produced 80 revisions with no lost update.
- **Corrupt files are kept.** If `focus.json` cannot be decoded, the app moves it aside as
  `focus.json.corrupt-<timestamp>` and warns you in the banner instead of silently starting empty.

## Testing without touching the real deck

Set `FOCUSDECK_HOME` to keep the state and settings somewhere else. The CLI and the app both honour it:

```bash
FOCUSDECK_HOME=/tmp/fd-sandbox focusdeck set "Sandbox test"
FOCUSDECK_HOME=/tmp/fd-sandbox focusdeck status
```

## The easy way: the CLI

```bash
focusdeck set "Ship the visuals engine" --source agent --project focus-deck
focusdeck overlay "Build failed on CI" --kind warn --ttl 30
focusdeck queue "Write the changelog" "Reply to Dana"
focusdeck done
focusdeck status --json
```

## Direct file example (single writer only)

For concurrent writers, use the CLI, which acquires the app’s file lock. This example is only for isolated, single-writer integrations.

```python
import json, os, time, uuid, tempfile
from datetime import datetime, timezone

import os

STATE = os.path.join(
    os.environ.get("FOCUSDECK_HOME", os.path.expanduser("~/Library/Application Support/FocusDeck")),
    "focus.json",
)


def fnv1a(text):
    """Same hash the app uses, so the cover matches the title."""
    value = 0xCBF29CE484222325
    for byte in text.encode("utf-8"):
        value ^= byte
        value = (value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return value

def set_focus(title, project=None, kind="agent"):
    state = {"revision": 0, "queue": [], "history": []}
    if os.path.exists(STATE):
        with open(STATE) as handle:
            state = json.load(handle)
    state["revision"] = int(state.get("revision", 0)) + 1
    state["writer"] = "agent"
    state["updatedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    state["current"] = {
        "id": str(uuid.uuid4()),
        "title": title,
        "source": kind,                    # "custom", "agent" or "todoist"
        "project": project,
        "startedAt": state["updatedAt"],
        "coverSeed": fnv1a(title.strip().lower()),   # optional; picks the artwork
    }
    directory = os.path.dirname(STATE)
    os.makedirs(directory, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=directory, delete=False) as handle:
        json.dump(state, handle, indent=2)
        temporary = handle.name
    os.replace(temporary, STATE)
```

## Ideas

- **A stop hook** in your agent harness: when a long job finishes, call
  `focusdeck overlay "Job finished: <name>" --kind agent` – you see it on the big screen without
  switching windows.
- **A morning job**: `focusdeck queue "$(todoist today | head -5)"`.
- **Focus timer**: `focusdeck set "Deep work: <task>"` when a Pomodoro starts.
- **Warn before you interrupt yourself**: `focusdeck overlay "3 agents are waiting" --kind warn`.
