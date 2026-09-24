# Output contract: API documents, `ok`, `dry_run`, `error`

Under `--output json` (or `XURL_OUTPUT=json` / `XURL_JSON=1`), `xr` answers one of four document kinds. Which one you
got is decided by the **exit code and the stream first**, and by the `status` key second:

| Exit     | Stream | `status` key | What it is                                                                                                    |
| -------- | ------ | ------------ | ------------------------------------------------------------------------------------------------------------- |
| 0        | stdout | **absent**   | An API-backed success: the X API document (`data`, plus `includes` / `meta` / `errors` when sent)             |
| 0        | stdout | **absent**   | `xr version`: `{"name":"xr","version":"4.1.0","xdk_rs":"0.1.1"}`, the one local verb with no `status`         |
| 0        | stdout | `"ok"`       | A local verb's success (`auth …`, `validate`, `skill …`): verb-specific keys beside `status`                  |
| 0        | stdout | `"dry_run"`  | A write verb's preflight under `--dry-run`: `would_succeed`, `exit_code`, and the inputs it validated         |
| non-zero | stderr | `"error"`    | A failure: kebab-case `reason`, `exit_code`, `message`, and `next_step` when a recovery exists                |

Two exceptions to the stream rule, both verified on `xr 4.1.0`:

- The `skill install` / `skill update` verbs write their error envelope to **stdout** with the non-zero exit
  (`missing-host` and `destination-not-empty` verified). Feature-detect on `status == "error"` there.
- An invalid `--output` value (`--output toml`) is a plain usage message on stderr at exit `2` (`Error: invalid value
  'toml' for '--output <OUTPUT>'`, ending `Try 'xr <cmd> --help'.`), because no structured mode was resolved. Every
  other flag-parsing failure (an unknown flag, a missing positional, a bad `--timeout`) is an `invalid-args` envelope
  whose `message` carries the parser's text without an `error:` prefix, ending with the same `Try '… --help'.` line.

Capture both streams when you intend to branch on the result: `RESPONSE=$(xr whoami --output json 2>&1)`. Capturing
stdout alone leaves the variable empty on exactly the path a script wants to inspect.

Verify the envelope variants against the bundled schema:

```bash
xr schema --envelope --output json        # declares the ok / dry_run / error variants and every error key
```

The schema's `ok` variant describes the local verbs. API-backed successes do not carry `status`, so `xr validate
--schema envelope` rejects them (`validation-failed`, "missing required string field `status`"); validate those against
the verb's own schema instead (`xr validate --schema posts`, `--schema user`, …). See
[Validating documents](#validating-documents).

## The four kinds

### API-backed success: the X API document, no `status`

```json
{
  "data": { "id": "42", "name": "Alice", "username": "alice" }
}
```

Every verb that calls the X API (`post`, `reply`, `quote`, `delete`, `read`, `search`, `whoami`, `user`, `timeline`,
`mentions`, `like` … `unbookmark`, `bookmarks`, `likes`, `follow` … `followers`, `mute` / `unmute` / `muted`, `block` /
`unblock` / `blocked`, `dm`, `dms`, `broadcasts moderators list` / `add` / `remove`, `usage`, `usage credits`, `media
upload`, `media status`, and raw mode) prints the X API document: `data` (an object for lookups and writes, an array
for list verbs), and `includes`, `meta` (`next_token`, `result_count`), `errors` (partial failures beside valid data)
when present. Typed verbs deserialize the body into the shape `xr schema <verb>` declares before printing, so a body the
type cannot hold is a `serialization` error, not a partial document.

Typed output is that shape, not the bytes X sent, in two ways that matter when reading fields:

- **Post vocabulary.** X still answers some endpoints with its pre-rename field names. Typed verbs print the name the
  spec uses and keep X's value: `edit_history_tweet_ids` reads as `edit_history_post_ids`, `public_metrics.retweet_count`
  as `repost_count`. Read the current names in typed output (the rename table comes from the vendored spec; a legacy
  spelling that is also a current name elsewhere in the spec is left as sent). Raw mode (`xr /2/...`) prints exactly
  what X sent, legacy names included. Text-mode `--verbose` prints one line per renamed key on stderr
  (`info: X sent edit_history_tweet_ids; read as edit_history_post_ids (array, length 1)`); structured output and
  `--quiet` suppress it.
- **Counters are filled.** Inside `public_metrics`, every counter the typed shape declares is printed, so one X did not
  send reads as `0`; optional fields X omitted elsewhere (`created_at`, `author_id`, …) stay absent. When "absent" and
  "zero" must differ for a counter, fetch the resource in raw mode (`xr /2/tweets/<id>`).

Three write verbs answer a confirmation object rather than the resource: `dm` prints `{"data":{"dm_conversation_id":
"…","dm_event_id":"…"}}` (the schema `dm` validates exactly that), and `broadcasts moderators add` / `remove` print
`{"data":{"moderator_user_ids":["…"]}}`, the moderator set after the change (schema `moderators`). `broadcasts
moderators list` is a plain user list (`{"data":[{id, username, name, …}]}`, schema `users`).

The record shapes are the API's; read the per-verb schema rather than hand-coding field paths:

```bash
xr schema post --output json | jaq '.properties.data'
```

### Local success: `status: "ok"`

```json
{ "status": "ok", "apps": [] }
```

Verbs that never touch the API answer `status: "ok"` with their own keys beside it:

| Verb                                                                                            | Top-level keys beside `status`                                             |
| ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `auth status`, `auth apps list`                                                                 | `apps` (array; see below)                                                  |
| `auth apps add`                                                                                 | `message`, `default`, `next_step`                                          |
| `auth apps update`, `auth apps remove`, `auth default`, `auth clear`, `auth app --bearer-token` | `message`                                                                  |
| `auth oauth2 --no-browser --step 1`                                                             | `auth_url`, `instructions`                                                 |
| `auth apps redirect-uri get`                                                                    | `app`, `effective_redirect_uri`, `effective_source`, `stored_redirect_uri` |
| `validate`                                                                                      | `schema`, `valid`                                                          |
| `skill install <host>`, `skill update <host>`                                                   | the per-host install record                                                |
| `skill install --all`, `skill update --all`                                                     | `action`, `installations`, `exit_code`                                     |

`auth default <app> <user>` prints two documents (the app message with `status`, then the user message without); parse
the first or run the two forms separately.

`xr version` is local but carries no `status`: under `--output json` it prints `{"name":"xr","version":"4.1.0",
"xdk_rs":"0.1.1"}` (the CLI version beside the `xdk-rs` library it links), `--output yaml` the same keys, and text mode
the line `xr 4.1.0`, or `xr 4.1.0 (xdk-rs 0.1.1)` with `--verbose`. `xr --version` is the plain clap line. Read
`.version`; `xr validate --schema envelope` rejects the document for the missing `status`.

**`auth status` and `auth apps list` wrap the array**: the shape is `{"status":"ok","apps":[...]}`, never a bare
top-level array. Every jq path into it starts at `.apps[]`:

```bash
xr auth status --output json | jaq -r '.apps[].name'
xr auth status --output json | jaq -r '.apps[] | select(.default) | .name'
xr auth apps list --output json | jaq -c '.apps[] | {name, client_id_hint, oauth2_users, bearer}'
```

An empty store still answers `{"status":"ok","apps":[]}`, so a loop over `.apps[]` needs no zero-app special case.

### Write-op preflight: `status: "dry_run"`

```json
{
  "status": "dry_run",
  "would_succeed": true,
  "exit_code": 0,
  "command": "post",
  "body": "…",
  "media_ids": []
}
```

Mandatory fields:

- `would_succeed` (boolean): true iff the inputs validated.
- `exit_code` (integer): the exit code the verb would have returned on actual execution.

The inputs the verb validated sit beside them: `command` (the verb name; `media-upload` for the upload,
`broadcasts-moderators-add` / `broadcasts-moderators-remove` for the moderator verbs), `body`, `media_ids`, `post_id`,
`target_username`, `file`, `media_type`, `category`. Check `would_succeed: true` AND `exit_code: 0` before re-running
without `--dry-run`.

Dry-run validates **inputs** and nothing else:

- It does not check credentials: an empty store still answers `would_succeed: true` for `xr post`. Confirm auth
  separately with `xr auth status --output json` before the live call.
- It does not read the filesystem: `xr media upload ./missing.png --dry-run` answers `would_succeed: true`; the live
  call answers `reason: "io"`, exit `5`.
- It echoes arguments as given: `xr reply <status URL> … --dry-run` reports the URL as `post_id`, and `xr block @handle
  --dry-run` reports `target_username: "@handle"`; the live request carries the extracted id and looks the handle up at
  `/2/users/by/username/handle` without the `@`.
- It runs **after** the verb's own confirmation gate: `delete`, `auth clear`, and `auth apps remove` answer `reason:
  "confirmation-required"`, exit `1`, when they cannot prompt, even under `--dry-run`. Pass `--force` for the preflight
  and the live call both (`--no-interactive` does not stand in for it: the verb still answers `confirmation-required`).
  No other write verb takes `--force`; `xr block @x --force` and `xr broadcasts moderators add @x --force` are
  `invalid-args`.

Emitted by every write op when `--dry-run` is set. Read ops ignore `--dry-run` and run for real. The `dry_run` variant's
description in `xr schema --envelope` says the extra context "lives in `payload`"; the envelope is flat, as shown above,
and there is no `payload` key.

### Failure: `status: "error"`

```json
{
  "status": "error",
  "reason": "auth-required",
  "exit_code": 77,
  "message": "Auth Error: NoAuthMethod: no authentication method available",
  "next_step": {
    "action": "register-app",
    "template": "xr auth apps add <name> --client-id <client-id> --client-secret <client-secret>"
  }
}
```

Mandatory fields:

- `reason` (string, kebab-case): typed kind from the set the release emits (catalog below); keep a default branch.
- `exit_code` (integer): the process exit code; the two always agree.

Optional fields, each **omitted entirely (not `null`) when absent**, so feature-detect by key presence:

- `message` (string): human-readable detail. On an HTTP failure it carries the API's problem document as a string.
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
{ "action": "show-help",    "command":  "xr auth status --help" }
```

A step carries **either** `command` (runnable verbatim by a non-TTY caller) **or** `template` (angle-bracket
placeholders only the caller can fill), never both; `enroll-app` carries only `docs`.

The six actions below are every one `xr 4.1.0` emits, and `xr schema --envelope` lists the same six. A newer `xr` can
add one without a major version bump, so give every branch on `action` a default: an action you do not recognize means
"read `message` and show the user the step", never "ignore it" and never "run its `command` unread". The same holds for
`reason` (see [Reason catalog](#reason-catalog)).

| `action`        | Meaning                                          | Do                                                           |
| --------------- | ------------------------------------------------ | ------------------------------------------------------------ |
| `register-app`  | No app carries client credentials                | Fill the `template` with real values and run it              |
| `sign-in`       | The target app has credentials but no token      | Run `command` verbatim; it is the headless two-step form     |
| `select-app`    | A different registered app is the one to use     | Run `command` verbatim (it names the app with `--app`)       |
| `inspect-store` | `~/.xurl` exists but could not be read or parsed | Run `command`; the `message` names the file path to inspect  |
| `enroll-app`    | X refused the app: a 403 naming enrollment       | Open `docs`; the fix is in the developer portal, not the CLI |
| `show-help`     | `unknown-command`: the word names no command     | Run `command`; it prints the help to read before retrying    |

`enroll-app` rides on `reason: "forbidden"` only when the 403 body contains `client-not-enrolled` or `client-forbidden`;
any other 403 is a bare `forbidden` with no `next_step`. `show-help` names the help of the nearest command (`xr auth
statsu` → `xr auth status --help`), of the family the word was typed under when nothing is close (`xr auth zzz` → `xr
auth --help`), or the root help (`xr --help`); the help is read-only, so running it needs no confirmation.

`next_step` also appears on one **success** envelope: `xr auth apps add` answers `status: "ok"` with a `sign-in` step so
the next command is already spelled out.

Not every failure carries one. `rate-limited`, `not-found`, `invalid-request`, `server-error`, and `api-error` never do;
`auth-required` from a forced `--auth app` with no bearer staged does not either, and neither does the `auth-required`
an HTTP 401 produces. Treat an absent `next_step` as "read `message`, then decide", never as a parse error.

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
if [ "$(printf '%s' "$RESPONSE" | jaq -r '.status // ""')" = "error" ] &&
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
    *)                                      # none, or an action a newer xr added: surface it, do not act on it
      printf '%s\n' "$(printf '%s' "$RESPONSE" | jaq -r '.message')" >&2
      printf '%s\n' "$(printf '%s' "$RESPONSE" | jaq -c '.next_step // empty')" >&2
      ;;
  esac
  exit 77
fi
```

`xr auth status` on an unreadable store answers `reason: "token-store"`, exit 77, with no `next_step`. The `message`
names the file. Back it up, then `xr auth clear --all --force` or move it aside, and re-run the auth flow.

## Reason catalog

Every reason `xr 4.1.0` emits, with the exit code it emits it at. A newer `xr` can add a reason without a major version
bump, so a script that branches on `reason` needs a default branch; the exit code still classifies an unknown reason
coarsely (`2` local usage, `3` back off, `77` credentials, `1` / `5` read `message`).

| `reason`                                                                            | `exit_code`             | What it means                                                                                                                          | First response                                                                                             |
| ----------------------------------------------------------------------------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `auth-required`                                                                     | 77                      | No usable credential for the verb, or HTTP 401                                                                                         | Follow `next_step` (recipe above); absent, read `message`                                                  |
| `token-store`                                                                       | 77                      | `~/.xurl` exists but could not be loaded                                                                                               | Inspect the path in `message`; back up; `xr auth clear --all --force`                                      |
| `auth-method-mismatch`                                                              | 2                       | `--auth X` (or the app's only scheme) is rejected by the endpoint                                                                      | Read `supported` / `other_apps_with_creds`; change `--auth` or `--app`                                     |
| `client-credentials-missing`                                                        | 2                       | `auth oauth2` on an app with no client id                                                                                              | Follow `next_step` (`register-app` when no app has one, `select-app` when another does)                    |
| `invalid-args`                                                                      | 2                       | Flag parsing failed (unknown flag, missing positional, bad value)                                                                      | Re-read `xr <cmd> --help`; fix the call                                                                    |
| `unknown-command`                                                                   | 2                       | Mistyped verb, including `xr <word> --help` / `--version` when the word names no command                                               | Run `next_step.command` (`show-help`); `suggestion` names the nearest verb when one is close               |
| `missing-host`                                                                      | 2                       | `skill install` / `skill update` without `<host>` or `--all` (on stdout)                                                               | Pick from `known_hosts`                                                                                    |
| `rate-limited`                                                                      | 3                       | HTTP 429                                                                                                                               | `xr usage --output json` → wait or pivot to caching                                                        |
| `not-found`                                                                         | 4                       | HTTP 404                                                                                                                               | Verify the post/user ID; some hits are normal                                                              |
| `forbidden`                                                                         | 1                       | HTTP 403                                                                                                                               | Read `message`; when it names enrollment the envelope carries an `enroll-app` `next_step`, open its `docs` |
| `invalid-request`                                                                   | 1                       | HTTP 400 or 422: X rejected the request body or parameters                                                                             | Read the API's problem document in `message`; fix the input, do not retry as-is                            |
| `server-error`                                                                      | 1                       | HTTP 5xx                                                                                                                               | Re-try once after a pause; if it persists, stop and report with the text-mode `--verbose` capture          |
| `api-error`                                                                         | 1                       | Any other HTTP failure status                                                                                                          | Read the status and body in `message`                                                                      |
| `network-error`                                                                     | 5                       | The request never got an answer: DNS, TCP, TLS, timeout                                                                                | Re-try once; check `--timeout` on slow networks                                                            |
| `invalid-method`                                                                    | 1                       | Wrong HTTP verb for an endpoint (raw mode)                                                                                             | Check the endpoint docs                                                                                    |
| `invalid-url`                                                                       | 1                       | Raw-mode URL is not absolute `http(s)://` or `/`-prefixed                                                                              | Fix the URL                                                                                                |
| `invalid-path-param`                                                                | 1                       | A path placeholder could not be substituted                                                                                            | Fix the argument                                                                                           |
| `validation`                                                                        | 1                       | Inputs failed a local check (`auth clear` without a selector; `xr schema <verb>` on a verb with no typed response, or an unknown name) | Read `message`; for `schema` it lists the valid names                                                      |
| `serialization`                                                                     | 1                       | A success body did not deserialize into the verb's typed shape                                                                         | A write most likely landed: do not retry it. A read: request its path (shown by `--verbose`) in raw mode   |
| `io`                                                                                | 5 (`1` from `validate`) | Local file or pipe error (a missing `media upload` path)                                                                               | Check the path / pipe / permissions                                                                        |
| `internal`                                                                          | 1                       | Unexpected runtime state                                                                                                               | File upstream with the text-mode `--verbose` output                                                        |
| `confirmation-required`                                                             | 1                       | `delete` / `auth clear` / `auth apps remove` could not prompt and had no `--force`                                                     | Re-run with `--force` after the user confirms (also needed under `--dry-run`)                              |
| `no-tty`                                                                            | 1                       | A prompt was needed and stdin is not a terminal                                                                                        | Pass the value as a flag, or `--no-interactive`                                                            |
| `unsupported-pagination`                                                            | 1                       | `--page` was passed; X has no offset paging                                                                                            | Use `--cursor` from `meta.next_token`                                                                      |
| `invalid-json`                                                                      | 1                       | `validate` input is not JSON                                                                                                           | Fix the input                                                                                              |
| `unknown-schema`                                                                    | 1                       | `validate --schema` names nothing bundled                                                                                              | Pick from `known_schemas`                                                                                  |
| `validation-failed`                                                                 | 1                       | `validate` input does not match the schema                                                                                             | Read `message` for the field-level error                                                                   |
| `home-not-set`                                                                      | 1                       | `skill` verb could not expand `~`                                                                                                      | Set `$HOME`                                                                                                |
| `remove-failed`                                                                     | 1                       | `skill update` could not clear the install dir                                                                                         | Check permissions on `install_dir`; remove it by hand                                                      |
| `destination-not-empty`, `destination-is-file`, `git-not-found`, `git-clone-failed` | 1                       | `skill install` preconditions (on stdout)                                                                                              | Read `install_dir` / `command_preview`; fix the destination or install `git`                               |

`skill update --all` also emits per-host entries with `status: "skipped"` and `reason: "not-installed"` at exit code 0.
Those are not errors: `update` refreshes what exists and passes over the rest.

## Pattern-match in scripts

Branch on the exit code, then on `status`. A statusless document at exit 0 is the API's answer:

```bash
EC=0
RESPONSE=$(xr post "hi" --dry-run --output json 2>&1) || EC=$?

if [ "$EC" -ne 0 ]; then
  REASON=$(printf '%s' "$RESPONSE" | jaq -r '.reason // "usage"')      # "usage" = clap text, not an envelope
  case "$REASON" in
    rate-limited) sleep 60 ;;
    auth-required)
      printf 'Re-auth needed: %s\n' \
        "$(printf '%s' "$RESPONSE" | jaq -r '.next_step.command // .next_step.template // "xr auth status"')" >&2
      exit 77 ;;
    *) printf 'Failed (%s): %s\n' "$REASON" "$RESPONSE" >&2; exit "$EC" ;;
  esac
fi

case "$(printf '%s' "$RESPONSE" | jaq -r '.status // "api"')" in
  dry_run)
    WOULD=$(printf '%s' "$RESPONSE" | jaq -r '.would_succeed')
    EXIT=$(printf '%s' "$RESPONSE" | jaq -r '.exit_code')
    [ "$WOULD" = "true" ] && [ "$EXIT" = "0" ] || exit 1
    # confirmed safe; re-run without --dry-run
    ;;
  ok)   ;;   # a local verb; read its keys
  api)  ;;   # an API document; read .data (should not happen for a --dry-run preflight)
  error) exit 1 ;;   # only the skill verbs put this on stdout
esac
```

`scripts/dry-run-gate.sh` and `scripts/paginate.sh` implement exactly this branching; prefer them over re-deriving it.

## Exit-code → envelope mapping

`xr` always sets both `exit_code` in the envelope AND the process exit code. They agree. Use the envelope's `reason` for
branching (finer-grained, easier to match; keep a default branch) and the exit code for coarse retry policy: back off on
`3`, give up on `2` (the cause is local), recover credentials on `77`.

| `exit_code` | `reason`(s)                                                                                                                                                                                                                                                                                            |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 0           | success (an API document, `status: ok`, a successful dry-run, or a `skipped` host under `skill update --all`)                                                                                                                                                                                          |
| 1           | every local or generic failure: `validation`, `serialization`, `internal`, the `validate` and `skill` verb-local reasons, `confirmation-required`, `no-tty`, `unsupported-pagination`; and every HTTP refusal that is not 401 / 404 / 429: `forbidden`, `invalid-request`, `server-error`, `api-error` |
| 2           | `invalid-args`, `unknown-command`, `auth-method-mismatch`, `client-credentials-missing`, `missing-host`; an invalid `--output` value is bare clap text at 2                                                                                                                                            |
| 3           | `rate-limited`                                                                                                                                                                                                                                                                                         |
| 4           | `not-found`                                                                                                                                                                                                                                                                                            |
| 5           | `network-error` (the request never got an answer) and `io` on file-access failures (`media upload`); `validate` reports its own `io` at `1`                                                                                                                                                            |
| 77          | `auth-required`, `token-store`                                                                                                                                                                                                                                                                         |

Exit `5` is shared by `network-error` and file-access `io`, and exit `1` by every non-401/404/429 API refusal and every
local failure, so a retry policy keyed on the exit code alone cannot tell "the server said no" from "the file is
missing". Branch on `reason`.

## Validating documents

`xr validate --schema <name>` checks a captured document against the bundled schema. Pick the schema by document kind:

```bash
xr whoami --output json 2>&1 | xr validate --schema user --output json       # API-backed success: the verb's schema
xr search "x" --output json | xr validate --schema posts --output json       # list verbs: the plural schema
xr post "hi" --dry-run --output json | xr validate --schema envelope --output json   # dry_run: the envelope
xr /2/missing --output json 2>&1 | xr validate --schema envelope --output json       # error: the envelope
```

Each answers `{"status":"ok","schema":"<name>","valid":true}` on a match. `--schema envelope` accepts the `error`,
`dry_run`, and local `ok` variants and rejects an API-backed success (no `status`), so a pipeline that validates
"whatever came back" needs the exit code first: non-zero → `envelope`, zero → the verb's schema. The accepted names are
`post`, `posts`, `user`, `users`, `dm`, `dms`, `dm-event`, `usage`, `credits`, `envelope`, `like`, `follow`, `delete`,
`repost`, `bookmark`, `mute`, `block`, `moderators`; anything else answers `unknown-schema` with the list in
`known_schemas`, and `xr validate --help` prints the same eighteen.

Three names do not map one-to-one onto a verb: `dm` validates the send confirmation `xr dm` prints, with its
`dm_conversation_id` and `dm_event_id`; `dm-event` a single event from a `dms` page; and `moderators` the
`moderator_user_ids` document that `broadcasts moderators add` / `remove` return. The `broadcasts moderators list` page
validates as `users`.

Useful in CI when capturing live responses for regression fixtures, since it confirms the bundled schema still describes
the wire shape after an `xr` upgrade.

## What about text mode?

Under `--output text` (the default) an error prints a human-readable `Error: …` line on stderr, followed by the same
recovery hint the envelope carries as `next_step` rendered as a `Run: …` sentence, and `xr` exits non-zero. A success
prints a formatted view on a TTY and the pretty-printed JSON document when stdout is a pipe. A `--dry-run` preflight
prints the validated inputs without `status` / `would_succeed`. **Do not parse text mode for automation.** Opt in to
`--output json` and read the contract above.
