# Template: post, reply, thread

Copy this template, fill the placeholders, and execute in order. Every step is gated by `--dry-run` first because `xr`
is configured against production X credentials and every write op hits real state.

## Pre-flight

```bash
xr auth status --output json                 # .apps[]: confirm the default app lists an oauth2_users entry
xr whoami --output json                      # confirm the active user is who you think
```

`whoami` succeeds with the API document `{"data":{"id":…,"username":…,"name":…}}` on stdout (no `status` key; that is
the normal success shape for API-backed verbs). If it exits `77` (`reason: "auth-required"`), its envelope on stderr
carries a `next_step` naming the fix; follow it via [templates/oauth2-setup.md](oauth2-setup.md) first.

## Preferred path: `scripts/dry-run-gate.sh`

The bundle ships a deterministic gate that runs the dry-run preflight, asserts `would_succeed=true && exit_code=0`,
prompts for confirmation (or honors `--yes` for headless callers), then `exec`s the live call. Use it for every write op
below:

```bash
# Interactive (TTY): gate prompts before going live.
~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh -- xr post "<TEXT>"

# Headless: caller has already obtained user confirmation.
RESP=$(~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh --yes -- xr post "<TEXT>")
ID=$(printf '%s' "$RESP" | jaq -r '.data.id')   # or jq
```

The script lives at `~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh` after `xr skill install claude_code` (or the
equivalent path on Codex / Cursor / Factory / Kiro / OpenCode). From the bundle directory, invoke
`./scripts/dry-run-gate.sh`. See [scripts/README.md](../scripts/README.md) for the full contract.

The rest of this template documents the manual path, useful when you need to inspect the dry-run envelope before
deciding, or when you want a different output format on the live call.

## Single post (manual path)

### 1. Dry-run

```bash
xr post "<TEXT>" --dry-run --output json
```

Expect a `status: "dry_run"`, `would_succeed: true`, `exit_code: 0` envelope on stdout, with the inputs it validated
beside them (`command`, `body`, `media_ids`; `post_id` for `reply` / `quote`). If `would_succeed` is `false`, the
payload names the failing input check (text too long, malformed ID). Dry-run validates inputs only; it does not check
credentials, which is why the pre-flight `whoami` above matters. Fix and re-run the dry-run before going live.

### 2. Live

```bash
xr post "<TEXT>" --output json
```

Capture the response. The live answer is the API document (`{"data":{"id":"…","text":"…"}}`, no `status` key); the
new post ID is at `data.id`:

```bash
POST_ID=$(xr post "<TEXT>" --output json | jaq -r '.data.id')
echo "Posted: $POST_ID"
```

Verify the schema is what you expect:

```bash
xr schema post --output json | jaq '.properties.data'
```

## Reply

```bash
xr reply <PARENT_ID> "<TEXT>" --dry-run --output json
xr reply <PARENT_ID> "<TEXT>" --output json
```

`<PARENT_ID>` accepts a bare integer OR a full post URL (`https://x.com/<user>/status/<id>`); `xr` extracts the ID for
the live request (`reply.in_reply_to_tweet_id`). The dry-run envelope echoes the argument as given, URL included.

## Quote post

```bash
xr quote <SOURCE_ID> "<TEXT>" --dry-run --output json
xr quote <SOURCE_ID> "<TEXT>" --output json
```

## Threading loop

A thread is a chain: each reply targets the previous post's ID. Use `scripts/dry-run-gate.sh --yes` per post so each
link is gated.

```bash
#!/usr/bin/env bash
set -euo pipefail

GATE=~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh
JQ=${JQ:-jaq}   # or jq

THREAD=(
  "<POST 1 TEXT>"
  "<POST 2 TEXT>"
  "<POST 3 TEXT>"
)

# After user-side confirmation in chat, go live one post at a time.
PARENT=""
for TEXT in "${THREAD[@]}"; do
  if [ -z "$PARENT" ]; then
    RESP=$("$GATE" --yes -- xr post "$TEXT")
  else
    RESP=$("$GATE" --yes -- xr reply "$PARENT" "$TEXT")
  fi
  PARENT=$(printf '%s' "$RESP" | "$JQ" -r '.data.id')
  printf 'Posted %s\n' "$PARENT"
done
```

Notes:

- **Always pause for user confirmation between the dry-run pass and the live pass.** A thread sends N writes; a wrong
  thread is N times harder to clean up than a wrong single post.
- **Don't try to post a thread in a tight loop without inspecting rate limits.** Check `xr usage --output json` first if
  you're posting more than a couple in quick succession.
- The dry-run envelope does NOT return a real post ID (none exists yet). The preview is `{"status":"dry_run",
  "would_succeed":true,"exit_code":0,"command":"post","body":"…","media_ids":[]}`; the variant is declared in `xr schema
  --envelope --output json`.

## Attaching media

Upload media first, capture the IDs, then attach via `--media-id` (repeatable):

```bash
MEDIA_ID_A=$(xr media upload ./a.png --media-type image/png --category tweet_image --output json | jaq -r '.data.id')
MEDIA_ID_B=$(xr media upload ./b.png --media-type image/png --category tweet_image --output json | jaq -r '.data.id')

xr post "<TEXT>" --media-id "$MEDIA_ID_A" --media-id "$MEDIA_ID_B" --dry-run --output json
xr post "<TEXT>" --media-id "$MEDIA_ID_A" --media-id "$MEDIA_ID_B" --output json
```

See [media-upload.md](media-upload.md) for the full upload state machine.

## Delete (when you must)

Destructive. Always confirm scope with the user before running, even on a dry-run. Run the live call through the gate
(it prompts on TTY, refuses without `--yes` off TTY):

```bash
~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh -- xr delete <POST_ID> --force
```

`--force` is the binary's own confirmation flag: `xr delete` prompts on a TTY and answers `reason:
"confirmation-required"`, exit `1`, when it cannot, **before** it considers `--dry-run`. The gate is the confirmation
step, so pass `--force` through it; without it the gate's own preflight is refused.

Manual path:

```bash
xr delete <POST_ID> --force --dry-run --output json     # --force is needed for the preflight off a TTY, too
# User confirms.
xr delete <POST_ID> --force --output json
```

Deleted posts cannot be restored from the X side.

## Parse errors

If a live call returns `status: "error"`:

- `reason: "rate-limited"` (exit `3`) → wait until reset, see `xr usage --output json`.
- `reason: "auth-required"` (exit `77`) → the envelope carries `next_step`; run its `command` verbatim or fill its
  `template` with the user's values, per [templates/oauth2-setup.md](oauth2-setup.md). Absent a `next_step`, a scope the
  verb needs wasn't granted.
- `reason: "auth-method-mismatch"` (exit `2`) → only a Bearer is staged, or `--auth` names a scheme the endpoint
  rejects; `supported` lists what it accepts.
- `reason: "confirmation-required"` (exit `1`) → the verb could not prompt; re-run with `--force` after the user
  confirms.
- `reason: "invalid-args"` (exit `2`) → re-read `xr post --help` (or `xr reply --help`), fix the call.
- `reason: "invalid-request"` (exit `1`) → X rejected the post itself (HTTP 400 / 422: too long, a duplicate, a bad
  `--media-id`); `message` carries X's problem document. Fix the input; the same call will not pass on retry.
- `reason: "forbidden"` (exit `1`) → X refused the write (HTTP 403). With `next_step.action: "enroll-app"`, open its
  `docs`; without one, the token lacks a scope or the tier lacks the endpoint, and re-running does not help.
- `reason: "server-error"` (exit `1`) → HTTP 5xx; one retry after a pause is reasonable.
- `reason: "network-error"` (exit `5`) → the request never got an answer; retry once, then check `--timeout`.
- `reason: "serialization"` (exit `1`) → the server response didn't deserialize into the typed shape. Re-run in text
  mode with `--verbose 2>wire.log` to capture the raw body and compare against `xr schema post --output json`.

Full reason → action map: [references/output-envelope.md](../references/output-envelope.md).
