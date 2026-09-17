# Todoist integration

What Focus Deck uses, and how it was verified.

Verified on 2026-09-15 with live HTTP calls (`curl -s -o /dev/null -w '%{http_code}'`)
and by reading the official specification that the docs site serves at
<https://developer.todoist.com/api/v1/> (the page embeds the full OpenAPI 3.1 document,
so `paths`, `components.schemas` and the "Pagination" tag text were read from it).
At the time of the original endpoint check, no token was available to the app, so the calls below were anonymous. An anonymous
answer of **401 / 403 proves that the endpoint exists and wants a token**;
**404 / 405 / 410 prove that the URL or the method is wrong**.

## Verified facts

| Item | Verified value | Evidence |
| --- | --- | --- |
| Base path | `https://api.todoist.com/api/v1` | OpenAPI `servers`; `GET /api/v1/tasks` -> **401** |
| Auth header | `Authorization: Bearer <token>` | "Authorization" tag in the spec; same header in every `x-codeSamples` curl example |
| List tasks | `GET /api/v1/tasks` | **401** anonymous |
| List tasks query params | `project_id`, `section_id`, `parent_id`, `label`, `ids`, `cursor`, `limit` (max 200, default 50) | OpenAPI `parameters` of `get_tasks_api_v1_tasks_get` |
| Filter tasks | `GET /api/v1/tasks/filter?query=<filter>` | **401** anonymous (`?query=today`) |
| Filter syntax | Todoist filter language, for example `today`, `overdue`, `today \| overdue`, `##Work`, `@errand & today`. A comma-joined multi-filter is **not** supported | `query` parameter description in the spec |
| Response envelope | `{"results": [...], "next_cursor": "..." or null}` | `PaginatedList_ItemSyncView_` schema; observed body `{"results": [], "next_cursor": null}` |
| Pagination | Cursor based: repeat the call with `cursor=<next_cursor>`; `null` means the end. Always resend the same filter together with the cursor | "Pagination" tag |
| Close (complete) | `POST /api/v1/tasks/{task_id}/close` | **401** anonymous; `GET` on the same path -> **405** |
| Reopen | `POST /api/v1/tasks/{task_id}/reopen` | **401** anonymous |
| Projects | `GET /api/v1/projects` | **401** anonymous |
| Quick Add | `POST /api/v1/tasks/quick` with `{"text": "Buy milk today #Shopping p1"}` | **403** anonymous (`Invalid token`) |
| Task JSON | `id`, `project_id`, `section_id` are strings; `due` is `null` or `{date, string, is_recurring, datetime, lang}`; `priority` is 1..4; `labels` is a string array; `checked` is the completion flag | `ItemSyncView` schema |
| REST v2 | Dead: `GET /rest/v2/tasks` -> **410 Gone**, body "This endpoint is deprecated." | also `/rest/v2/projects` -> **410** |
| Sync v9 | `POST /sync/v9/sync` -> **410 Gone** | also `GET /api/v1/sync` -> **405** (POST only) |
| Non-existent paths | `POST /api/v1/quick/add` -> **404**, `GET /v1/tasks` -> **404** | |

Error bodies are JSON, for example the real anonymous answer of `GET /api/v1/tasks`:

```json
{"error":"Unauthorized","error_code":477,
 "error_extra":{"event_id":"...","retry_after":1280},
 "error_tag":"UNAUTHORIZED","http_code":401}
```

The response sample for one task, taken from the docs:

```json
{"user_id":"1234567","id":"6XGgmFVcrG5RRjVr","project_id":"6XGgm6PHrGgMpCFX",
 "section_id":"6fFPHV272WWh3gpW","labels":["priority"],
 "due":{"date":"2025-02-12","is_recurring":false,"lang":"en","string":"tomorrow"},
 "priority":1,"content":"Buy milk","description":"Pick up organic milk","checked":false}
```

## What the first draft got wrong

Fixed in `Sources/FocusDeckKit/TodoistClient.swift`:

1. The filter was sent as `GET /api/v1/tasks?filter=...`. `/tasks` has no `filter` parameter.
   A filter must go to `GET /api/v1/tasks/filter?query=...`.
2. No pagination. The draft read `results` once and silently dropped the rest of the list.
   The client now follows `next_cursor` up to 5 pages of 200 items.
3. Decoding was strict. A missing `description`, a `null` `due`, a numeric id or a string
   `priority` made the whole list fail to decode. Decoding is now tolerant.
4. Quick Add was missing. It is `POST /api/v1/tasks/quick` (body key `text`), not
   `/api/v1/quick/add` (which answers 404).
5. `complete(taskID:)` sent a JSON `{}` body. The close endpoint takes no body.

Endpoints that were confirmed correct in the draft: base path, `Authorization: Bearer`,
`POST /api/v1/tasks/{id}/close`, `GET /api/v1/projects` and the `{"results": [...]}` envelope.

## How to create and paste a token

1. Open <https://app.todoist.com/app/settings/integrations> (redirects to the Developer tab,
   `.../integrations/developer`, both answer HTTP 200).
2. Scroll to **API token** and copy the personal token string
   The token has full access to the account. Treat it like a password.
3. In Focus Deck press `⌘,` to open Settings, find the **Todoist** group, paste the token
   into the secure field and click **Save**.
   The app stores it in the macOS keychain under service `com.focusdeck.app`,
   account `todoist-api-token`; it never writes the token to a file.
4. Click **Test connection** to confirm ("Todoist connection OK."). Set the **Filter**
   (default `today`, for example `##Work` or `@errand & today`) and press **Apply**.
   **Sync now** pulls the list immediately; **Sync from Todoist** enables the timer.
5. To remove the token, click **Disconnect**. The keychain item is deleted.

## Tests

`Tests/FocusDeckKitTests/TodoistClientTests.swift` is offline. It decodes the real-shape
fixtures in `Tests/FocusDeckKitTests/Fixtures/` and stubs `URLProtocol` for request checks,
so `swift test` never opens a socket.

## Tasks created in Focus Deck

The editor and picker send an `item_add` command to `POST /api/v1/sync`, using
`application/x-www-form-urlencoded` with a JSON-encoded `commands` field. The content
is kept literal and `due.date` is today's local `YYYY-MM-DD` date. Omitting `project_id`
selects Inbox. The implementation checks the command's `sync_status`, resolves its
`temp_id_mapping`, and reads the task from `GET /api/v1/tasks/{id}` before adopting it.
The command UUID is reused when retrying the same draft within the running app.

The resulting focus item has source `todoist` and ID `todoist:{id}`, so Done uses the
existing close endpoint and advances only after success. The app-model tests cover
creation, local persistence, completion, failures, concurrent focus changes, and retries.
See the [official Sync documentation](https://developer.todoist.com/api/v1/#tag/Sync)
for request encoding and command idempotency.
