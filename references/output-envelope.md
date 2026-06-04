# Output envelope — `ok` / `dry_run` / `error`

When `xr` runs under `--output json` (or `XURL_OUTPUT=json` / `XURL_JSON=1`), every response is one of three envelope
variants. The discriminator is the `status` field. Always match on `status` first.

Verify the live shape against the bundled schema:

```bash
xr schema --envelope --output json
```

## Variants

### `status: "ok"` — success

```json
{
  "status": "ok",
  "data": { "...verb-specific payload..." }
}
```

Verb-specific fields appear at the top level (merged flat for legibility). The exact shape per command is in `xr schema
--command <name> --output json`. The `data` field name varies — read the per-command schema rather than hand-coding
field paths.

### `status: "dry_run"` — write-op preflight

```json
{
  "status": "dry_run",
  "would_succeed": true,
  "exit_code": 0,
  "command": "post",
  "...verb-specific preview fields..."
}
```

Mandatory fields:

- `would_succeed` (boolean) — true iff every precondition checked clean.
- `exit_code` (integer) — the exit code the verb would have returned on actual execution.

Additional context (command name, body preview, target IDs) lives at the top level. Agents should check `would_succeed:
true` AND `exit_code: 0` before re-running without `--dry-run`.

Emitted by every write op when `--dry-run` is set. Read ops ignore `--dry-run` and return a normal `ok` envelope.

### `status: "error"` — failure

```json
{
  "status": "error",
  "reason": "auth-required",
  "exit_code": 2,
  "message": "no OAuth2 token staged for app 'default'"
}
```

Mandatory fields:

- `reason` (string, kebab-case) — typed kind from a **closed set**:
- `auth-required`
- `rate-limited`
- `not-found`
- `network-error`
- `invalid-args`
- `invalid-method`
- `validation`
- `serialization`
- `io`
- `token-store`
- `exit_code` (integer) — structured exit code; see [agent-flags.md § exit codes](agent-flags.md).

Optional field:

- `message` (string) — human-readable detail. **Omitted entirely (not `null`) when absent**, so feature-detect by key
  presence: `"message" in envelope`.

## Reason → action lookup

| `reason`         | What it means                          | First response                                      |
| ---------------- | -------------------------------------- | --------------------------------------------------- |
| `auth-required`  | No usable credential for the verb      | `xr auth status` → run the right auth flow → re-try |
| `rate-limited`   | HTTP 429                               | `xr usage --output json` → wait or pivot to caching |
| `not-found`      | HTTP 404                               | Verify the post/user ID; some hits are normal       |
| `network-error`  | DNS / TCP / TLS / timeout              | Re-try once; check `xr --timeout` if slow networks  |
| `invalid-args`   | CLI rejected the inputs before calling | Re-read `xr <cmd> --help`; fix the call             |
| `invalid-method` | Wrong HTTP verb for an endpoint        | Raw-mode only; check the endpoint docs              |
| `validation`     | Response didn't deserialize cleanly    | Diff against `xr schema --command <name>`           |
| `serialization`  | Response couldn't be re-emitted        | Re-run with `--verbose` to capture the wire body    |
| `io`             | Local file or pipe error               | Check the path / pipe / permissions                 |
| `token-store`    | `~/.xurl` is broken                    | `xr auth status` → `xr auth clear` → re-run flow    |

## Pattern-match in scripts

```bash
RESPONSE=$(xr post "hi" --dry-run --output json)

STATUS=$(printf '%s' "$RESPONSE" | jaq -r '.status')
case "$STATUS" in
  dry_run)
    WOULD=$(printf '%s' "$RESPONSE" | jaq -r '.would_succeed')
    EXIT=$(printf '%s' "$RESPONSE" | jaq -r '.exit_code')
    [ "$WOULD" = "true" ] && [ "$EXIT" = "0" ] || exit 1
    # confirmed safe; re-run without --dry-run
    ;;
  error)
    REASON=$(printf '%s' "$RESPONSE" | jaq -r '.reason')
    case "$REASON" in
      rate-limited) sleep 60 ;;
      auth-required) printf 'Re-auth needed: xr auth oauth2\n' >&2; exit 2 ;;
      *) printf 'Failed: %s\n' "$REASON" >&2; exit 1 ;;
    esac
    ;;
  ok)
    # normal path; should not happen for a --dry-run preflight
    ;;
esac
```

## Exit-code → envelope mapping

`xr` always sets both `exit_code` in the envelope AND the process exit code. They agree. Use the envelope's `exit_code`
to plan re-tries (e.g., back off on `3` for `rate-limited`, give up on `2` for `auth-required` and `invalid-args` since
the cause is local).

| `exit_code` | Most common `reason`(s)                            |
| ----------- | -------------------------------------------------- |
| 0           | success (`status: ok` or successful dry-run)       |
| 1           | `validation`, `serialization`, `io`, `token-store` |
| 2           | `auth-required`, `invalid-args`, `invalid-method`  |
| 3           | `rate-limited`                                     |
| 4           | `not-found`                                        |
| 5           | `network-error`                                    |

(The `reason → exit_code` mapping is enforced by `xurl::error`; consult the source if a corner case surprises you.)

## Validating envelopes

Round-trip any captured envelope through `xr validate --schema envelope`:

```bash
cat captured.json | xr validate --schema envelope --output json
```

Useful in CI when capturing live API responses for regression fixtures — confirms the bundled schema still describes the
wire shape after a `xr` upgrade.

## What about text mode?

When `--output text`, errors print a human-readable line on stderr and `xr` exits non-zero. There is no envelope. **Do
not parse text mode for automation.** It will eventually break. Always opt in to `--output json` (or jsonl).
