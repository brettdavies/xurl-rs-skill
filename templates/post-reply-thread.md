# Template — post, reply, thread

Copy this template, fill the placeholders, and execute in order. Every step is gated by `--dry-run` first because `xr`
is configured against production X credentials and every write op hits real state.

## Pre-flight

```bash
xr auth status --output json                 # confirm OAuth2 PKCE is staged, not expired
xr whoami --output json                      # confirm the active user is who you think
```

If `whoami` fails with `reason: "auth-required"`, run [templates/oauth2-setup.md](oauth2-setup.md) first.

## Single post

### 1. Dry-run

```bash
xr post "<TEXT>" --dry-run --output json
```

Expect a `status: "dry_run"`, `would_succeed: true`, `exit_code: 0` envelope. If `would_succeed` is `false`, the
envelope's payload names the failing precondition (text too long, missing scope, app not registered). Fix and re-run the
dry-run before going live.

### 2. Live

```bash
xr post "<TEXT>" --output json
```

Capture the response. The new post ID is at the `data.id` path of the `ok` envelope:

```bash
POST_ID=$(xr post "<TEXT>" --output json | jaq -r '.data.id')
echo "Posted: $POST_ID"
```

Verify the schema is what you expect:

```bash
xr schema --command post --output json | jaq '.properties.data'
```

## Reply

```bash
xr reply <PARENT_ID> "<TEXT>" --dry-run --output json
xr reply <PARENT_ID> "<TEXT>" --output json
```

`<PARENT_ID>` accepts a bare integer OR a full post URL (`https://x.com/<user>/status/<id>`) — `xr` parses the URL and
extracts the ID.

## Quote post

```bash
xr quote <SOURCE_ID> "<TEXT>" --dry-run --output json
xr quote <SOURCE_ID> "<TEXT>" --output json
```

## Threading loop

A thread is a chain: each reply targets the previous post's ID.

```bash
#!/usr/bin/env bash
set -euo pipefail

THREAD=(
  "<POST 1 TEXT>"
  "<POST 2 TEXT>"
  "<POST 3 TEXT>"
)

# Confirm the entire thread with --dry-run first.
PARENT=""
for TEXT in "${THREAD[@]}"; do
  if [ -z "$PARENT" ]; then
    xr post "$TEXT" --dry-run --output json --quiet
  else
    xr reply "$PARENT" "$TEXT" --dry-run --output json --quiet
  fi
  PARENT="<placeholder-for-dry-run-target>"   # dry-run doesn't return a real id
done

# After human confirms, go live.
PARENT=""
for TEXT in "${THREAD[@]}"; do
  if [ -z "$PARENT" ]; then
    RESP=$(xr post "$TEXT" --output json --quiet)
  else
    RESP=$(xr reply "$PARENT" "$TEXT" --output json --quiet)
  fi
  PARENT=$(printf '%s' "$RESP" | jaq -r '.data.id')
  echo "Posted $PARENT"
done
```

Notes:

- **Always pause for user confirmation between the dry-run pass and the live pass.** A thread sends N writes; a wrong
  thread is N times harder to clean up than a wrong single post.
- **Don't try to post a thread in a tight loop without inspecting rate limits.** Check `xr usage --output json` first if
  you're posting more than a couple in quick succession.
- The dry-run envelope does NOT return a real post ID (none exists yet). The shape of the dry-run preview is in `xr
  schema --command post --output json` under the `dry_run` variant.

## Attaching media

Upload media first, capture the IDs, then attach via `--media-id` (repeatable):

```bash
MEDIA_ID_A=$(xr media upload ./a.png --media-type image/png --category tweet_image --output json | jaq -r '.data.media_id')
MEDIA_ID_B=$(xr media upload ./b.png --media-type image/png --category tweet_image --output json | jaq -r '.data.media_id')

xr post "<TEXT>" --media-id "$MEDIA_ID_A" --media-id "$MEDIA_ID_B" --dry-run --output json
xr post "<TEXT>" --media-id "$MEDIA_ID_A" --media-id "$MEDIA_ID_B" --output json
```

See [media-upload.md](media-upload.md) for the full upload state machine.

## Delete (when you must)

Destructive. Always confirm scope with the user before running, even on a dry-run.

```bash
xr delete <POST_ID> --dry-run --output json
# User confirms.
xr delete <POST_ID> --output json
```

Deleted posts cannot be restored from the X side.

## Parse errors

If a live call returns `status: "error"`:

- `reason: "rate-limited"` → wait until reset, see `xr usage --output json`.
- `reason: "auth-required"` → re-run [templates/oauth2-setup.md](oauth2-setup.md), confirm scopes.
- `reason: "invalid-args"` → re-read `xr post --help` (or `xr reply --help`), fix the call.
- `reason: "validation"` → the server response didn't deserialize. Re-run with `--verbose` to capture the raw body and
  compare against `xr schema --command post`.

Full reason → action map: [references/output-envelope.md](../references/output-envelope.md).
