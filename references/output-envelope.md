# Output envelope: `ok` / `dry_run` / `error`

When `xr` runs under `--output json` (or `XURL_OUTPUT=json` / `XURL_JSON=1`), every response is one of three envelope
variants. The discriminator is the `status` field. Always match on `status` first.

Success and dry-run envelopes go to **stdout**. Error envelopes go to **stderr**. Capture both when you intend to branch
on the result: `RESPONSE=$(xr whoami --output json 2>&1)`.

Verify the live shape against the bundled schema:

```bash
xr schema --envelope --output json
```

## Variants

### `status: "ok"`, success

```json
{
  "status": "ok",
  "data": { "...verb-specific payload..." }
}
```

Verb-specific fields sit at the top level beside `status`. API-backed verbs (`post`, `whoami`, `search`, …) carry
`data`, plus `meta` / `includes` / `errors` when the API returns them. Local verbs carry their own keys instead:

| Verb                                                                                            | Top-level keys beside `status`                                             |
| ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `auth status`, `auth apps list`                                                                 | `apps` (array; see below)                                                  |
| `auth apps add`                                                                                 | `message`, `default`, `next_step`                                          |
| `auth apps update`, `auth apps remove`, `auth default`, `auth clear`, `auth app --bearer-token` | `message`                                                                  |
| `auth oauth2 --no-browser --step 1`                                                             | `auth_url`, `instructions`                                                 |
| `auth apps redirect-uri get`                                                                    | `app`, `effective_redirect_uri`, `effective_source`, `stored_redirect_uri` |
| `validate`                                                                                      | `schema`, `valid`                                                          |
| `skill install <host>`, `skill update <host>`                                                   | the per-host install envelope                                              |
| `skill install --all`, `skill update --all`                                                     | `action`, `installations`, `exit_code`                                     |

The per-command schema is in `xr schema <name> --output json`. Read it rather than hand-coding field paths.

**`auth status` and `auth apps list` wrap the array**: the shape is `{"status":"ok","apps":[...]}`, never a bare
top-level array. Every jq path into it starts at `.apps[]`:

```bash
xr auth status --output json | jaq -r '.apps[].name'
xr auth status --output json | jaq -r '.apps[] | select(.default) | .name'
xr auth apps list --output json | jaq -c '.apps[] | {name, client_id_hint, oauth2_users, bearer}'
```

An empty store still answers `{"status":"ok","apps":[]}`, so a loop over `.apps[]` needs no zero-app special case.

### `status: "dry_run"`, write-op preflight

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

- `would_succeed` (boolean): true iff the inputs validated.
- `exit_code` (integer): the exit code the verb would have returned on actual execution.

Additional context (command name, body preview, target IDs) lives at the top level. Check `would_succeed: true` AND
`exit_code: 0` before re-running without `--dry-run`.

Dry-run validates **inputs**, not credentials: a store with no tokens still returns `would_succeed: true` for `xr post`.
Confirm auth separately with `xr auth status --output json` before the live call.

Emitted by every write op when `--dry-run` is set. Read ops ignore `--dry-run` and return a normal `ok` envelope.

### `status: "error"`, failure

```json
{
  "status": "error",
  "reason": "auth-required",
  "exit_code": 77,
  "message": "Auth Error: NoAuthMethod: no authentication method available",
  "next_step": {
    "action": "sign-in",
    "command": "xr auth oauth2 --no-browser --step 1"
  }
}
```

Mandatory fields:

- `reason` (string, kebab-case): typed kind from a **closed set** (catalog below).
- `exit_code` (integer): the process exit code; the two always agree.

Optional fields, each **omitted entirely (not `null`) when absent**, so feature-detect by key presence:

- `message` (string): human-readable detail.
- `next_step` (object): what to do next, when a recovery step exists. See [`next_step`](#next_step) below.
- The offending value when there is one: `command` (the mistyped verb, or the verb a confirmation gate blocked),
  `schema`, `host`, `post_id`, `name`, `app`.
- Enumerations that bound the fix: `suggestion` (nearest real command), `known_schemas`, `known_hosts`, `supported`
  (auth schemes the endpoint accepts), `available_in_app`, `other_apps_with_creds`.
- Request context on auth-matrix failures: `endpoint`, `method`, `rendered_url`, `requested`.

Every key the runtime can emit is declared in `xr schema --envelope --output json` under the `error` variant.

## `next_step`

An error that knows how to recover carries a `next_step` object:

```json
{ "action": "register-app", "template": "xr auth apps add <name> --client-id <client-id> --client-secret <client-secret>" }
{ "action": "sign-in",      "command":  "xr auth oauth2 --no-browser --step 1" }
{ "action": "select-app",   "command":  "xr auth oauth2 --no-browser --step 1 --app other-app" }
{ "action": "inspect-store","command":  "xr auth status" }
{ "action": "enroll-app",   "docs":     "https://github.com/brettdavies/xurl-rs#x-platform-enrollment" }
```

`action` is a closed set. A step carries **either** `command` (runnable verbatim by a non-TTY caller) **or** `template`
(angle-bracket placeholders only the caller can fill), never both; `enroll-app` carries only `docs`.

| `action`        | Meaning                                          | Do                                                           |
| --------------- | ------------------------------------------------ | ------------------------------------------------------------ |
| `register-app`  | No app carries client credentials                | Fill the `template` with real values and run it              |
| `sign-in`       | The target app has credentials but no token      | Run `command` verbatim; it is the headless two-step form     |
| `select-app`    | A different registered app is the one to use     | Run `command` verbatim (it names the app with `--app`)       |
| `inspect-store` | `~/.xurl` exists but could not be read or parsed | Run `command`; the `message` names the file path to inspect  |
| `enroll-app`    | X refused the app (HTTP 403)                     | Open `docs`; the fix is in the developer portal, not the CLI |

`next_step` also appears on one **success** envelope: `xr auth apps add` answers `status: "ok"` with a `sign-in` step so
the next command is already spelled out.

## Exit 77 recipe

Exit code `77` (`EX_NOPERM`) means no usable credential: `reason: "auth-required"` or `reason: "token-store"`. It is
distinct from `2`, which is a usage fault (bad flags, or `--auth X` against an endpoint that rejects `X`). On 77, read
the answer from the envelope instead of guessing:

```bash
xr auth status --output json                 # {"status":"ok","apps":[...]}; each entry carries client_id_hint and bearer
xr whoami --output json 2>&1 >/dev/null      # the failure itself, carrying next_step
```

Then branch on `next_step.action`:

```bash
RESPONSE=$(xr whoami --output json 2>&1)
if [ "$(printf '%s' "$RESPONSE" | jaq -r '.status')" = "error" ] &&
   [ "$(printf '%s' "$RESPONSE" | jaq -r '.exit_code')" = "77" ]; then
  ACTION=$(printf '%s' "$RESPONSE" | jaq -r '.next_step.action // "none"')
  case "$ACTION" in
    sign-in|select-app|inspect-store)
      CMD=$(printf '%s' "$RESPONSE" | jaq -r '.next_step.command')
      printf 'Run: %s\n' "$CMD" >&2        # safe to exec verbatim; sign-in is the two-step headless form
      ;;
    register-app)
      printf 'Register an app: %s\n' "$(printf '%s' "$RESPONSE" | jaq -r '.next_step.template')" >&2
      ;;                                    # needs values only the user has; ask, do not invent
    enroll-app)
      printf 'Enroll the app: %s\n' "$(printf '%s' "$RESPONSE" | jaq -r '.next_step.docs')" >&2
      ;;
    none)
      printf '%s\n' "$(printf '%s' "$RESPONSE" | jaq -r '.message')" >&2
      ;;
  esac
  exit 77
fi
```

`xr auth status` on an unreadable store answers `reason: "token-store"`, exit 77, with no `next_step`. The `message`
names the file. Back it up, then `xr auth clear --all --force` or move it aside, and re-run the auth flow.

## Reason catalog

Closed set. Exit codes are what the binary emits today.

| `reason`                                                                            | `exit_code`             | What it means                                                               | First response                                                                                              |
| ----------------------------------------------------------------------------------- | ----------------------- | --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `auth-required`                                                                     | 77                      | No usable credential for the verb, or HTTP 401                              | Follow `next_step` (recipe above)                                                                           |
| `token-store`                                                                       | 77                      | `~/.xurl` exists but could not be loaded                                    | Inspect the path in `message`; back up; `xr auth clear --all --force`                                       |
| `auth-method-mismatch`                                                              | 2                       | `--auth X` (or the app's only scheme) is rejected by the endpoint           | Read `supported` / `other_apps_with_creds`; change `--auth` or `--app`                                      |
| `client-credentials-missing`                                                        | 2                       | `auth oauth2` on an app with no client id                                   | Follow `next_step` (`select-app`, or register)                                                              |
| `invalid-args`                                                                      | 2                       | Flag parsing failed                                                         | Re-read `xr <cmd> --help`; fix the call                                                                     |
| `unknown-command`                                                                   | 2                       | Mistyped verb                                                               | Use `suggestion` when present                                                                               |
| `missing-host`                                                                      | 2                       | `skill install` / `skill update` without `<host>` or `--all`                | Pick from `known_hosts`                                                                                     |
| `rate-limited`                                                                      | 3                       | HTTP 429                                                                    | `xr usage --output json` → wait or pivot to caching                                                         |
| `not-found`                                                                         | 4                       | HTTP 404                                                                    | Verify the post/user ID; some hits are normal                                                               |
| `network-error`                                                                     | 1                       | DNS / TCP / TLS / timeout, or a non-401/404/429 HTTP failure                | Re-try once; check `--timeout` on slow networks. A 403 refusing the app carries an `enroll-app` `next_step` |
| `invalid-method`                                                                    | 1                       | Wrong HTTP verb for an endpoint (raw mode)                                  | Check the endpoint docs                                                                                     |
| `invalid-url`                                                                       | 1                       | Raw-mode URL is not absolute `http(s)://` or `/`-prefixed                   | Fix the URL                                                                                                 |
| `invalid-path-param`                                                                | 1                       | A path placeholder could not be substituted                                 | Fix the argument                                                                                            |
| `validation`                                                                        | 1                       | Inputs failed a local check, or a response didn't deserialize               | Read `message`; diff against `xr schema <name>`                                                             |
| `serialization`                                                                     | 1                       | Response couldn't be re-emitted                                             | Re-run with `--verbose` to capture the wire body                                                            |
| `io`                                                                                | 5 (`1` from `validate`) | Local file or pipe error (a missing `media upload` path)                    | Check the path / pipe / permissions                                                                         |
| `internal`                                                                          | 1                       | Unexpected runtime state                                                    | File upstream with `--verbose` output                                                                       |
| `confirmation-required`                                                             | 1                       | A destructive verb ran without a TTY or `--no-interactive` and no `--force` | Re-run with `--force` after the user confirms                                                               |
| `no-tty`                                                                            | 1                       | A prompt was needed and stdin is not a terminal                             | Pass the value as a flag, or `--no-interactive`                                                             |
| `unsupported-pagination`                                                            | 1                       | `--page` was passed; X has no offset paging                                 | Use `--cursor` from `meta.next_token`                                                                       |
| `invalid-json`                                                                      | 1                       | `validate` input is not JSON                                                | Fix the input                                                                                               |
| `unknown-schema`                                                                    | 1                       | `validate --schema` names nothing bundled                                   | Pick from `known_schemas`                                                                                   |
| `validation-failed`                                                                 | 1                       | `validate` input does not match the schema                                  | Read `message` for the field-level error                                                                    |
| `home-not-set`                                                                      | 1                       | `skill` verb could not expand `~`                                           | Set `$HOME`                                                                                                 |
| `remove-failed`                                                                     | 1                       | `skill update` could not clear the install dir                              | Check permissions on `install_dir`; remove it by hand                                                       |
| `destination-not-empty`, `destination-is-file`, `git-not-found`, `git-clone-failed` | 1                       | `skill install` preconditions                                               | Read `install_dir` / `command_preview`; fix the destination or install `git`                                |

`skill update --all` also emits per-host entries with `status: "skipped"` and `reason: "not-installed"` at exit code 0.
Those are not errors: `update` refreshes what exists and passes over the rest.

## Pattern-match in scripts

```bash
RESPONSE=$(xr post "hi" --dry-run --output json 2>&1)

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
      auth-required)
        printf 'Re-auth needed: %s\n' \
          "$(printf '%s' "$RESPONSE" | jaq -r '.next_step.command // .next_step.template // "xr auth status"')" >&2
        exit 77 ;;
      *) printf 'Failed: %s\n' "$REASON" >&2; exit 1 ;;
    esac
    ;;
  ok)
    # normal path; should not happen for a --dry-run preflight
    ;;
esac
```

## Exit-code → envelope mapping

`xr` always sets both `exit_code` in the envelope AND the process exit code. They agree. Use the envelope's `reason` for
branching (closed set, easier to match) and the exit code for coarse retry policy: back off on `3`, give up on `2` (the
cause is local), recover credentials on `77`.

| `exit_code` | `reason`(s)                                                                                                                                                                                            |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 0           | success (`status: ok`, a successful dry-run, or a `skipped` host under `skill update --all`)                                                                                                           |
| 1           | every local or generic failure: `validation`, `serialization`, `internal`, `network-error`, the `validate` and `skill` verb-local reasons, `confirmation-required`, `no-tty`, `unsupported-pagination` |
| 2           | `invalid-args`, `unknown-command`, `auth-method-mismatch`, `client-credentials-missing`, `missing-host`                                                                                                |
| 3           | `rate-limited`                                                                                                                                                                                         |
| 4           | `not-found`                                                                                                                                                                                            |
| 5           | `io` on file-access failures (`media upload`); `validate` reports its own `io` at `1`                                                                                                                  |
| 77          | `auth-required`, `token-store`                                                                                                                                                                         |

`xr --help` labels `5` "network error"; the runtime maps `network-error` to `1` and file-access `io` to `5`.
Branch on `reason`, not on `5`.

## Validating envelopes

Round-trip any captured envelope through `xr validate --schema envelope`:

```bash
xr whoami --output json 2>&1 | xr validate --schema envelope --output json
```

Answers `{"status":"ok","schema":"envelope","valid":true}` for any of the three variants. Useful in CI when capturing
live responses for regression fixtures, since it confirms the bundled schema still describes the wire shape after an
`xr` upgrade.

## What about text mode?

When `--output text`, errors print a human-readable line on stderr and `xr` exits non-zero. There is no envelope, but
the same recovery hint the envelope carries as `next_step` is printed as a `Run: …` line. **Do not parse text mode for
automation.** It will eventually break. Always opt in to `--output json` (or jsonl).
