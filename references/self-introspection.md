# Self-introspection: let the binary teach you

`xr` is designed for agents. It ships five read-only commands that describe its own surface, schemas, and runtime state.
Reach for them before reading anything else. They are always safe to run: no credentials needed for most, no API calls
for any except `auth status` (which only inspects the local token store).

## The five helpers

### 1. `xr examples`: curated invocation gallery

```bash
xr examples
```

Plain-text gallery organized by use case: AUTHENTICATE, POST AND READ, MANAGE SOCIAL GRAPH, INSPECT YOUR ACCOUNT, DIRECT
MESSAGES, MEDIA UPLOAD, RAW MODE, INSPECT SCHEMAS, MULTI-APP, ENVIRONMENT VARIABLE PRECEDENCE. About 130 lines. Each
command appears with two or three canonical invocations (text mode, then `--output json`, sometimes piped to `jaq`).
This is the fastest way to learn the shape of any workflow.

One caveat: the gallery's `xr bookmarks -n 100 --output jsonl | jaq '.id'` line answers `null`, because `--output jsonl`
prints the whole document rather than one record per line. Filter the document instead: `--output json | jaq -c
'.data[]?'`. See [agent-flags.md § Output format](agent-flags.md#output-format).

### 2. `xr <command> --help`: per-command flag matrix and examples

```bash
xr post --help
xr search --help
xr media upload --help
```

Every command's `--help` includes:

- The exact positional argument shape.
- The full flag matrix (per-command flags + global agent flags).
- Env-var equivalents (`[env: XURL_OUTPUT=]`) on every flag that has one.
- Three to five curated examples at the bottom.

When in doubt about whether a flag exists, run `--help` rather than guessing.

### 3. `xr schema`: typed response shapes

```bash
xr schema --list                            # 39 rows: <name>  <Rust type>, one per response shape
xr schema post --output json                # JSON Schema for the `post` response
xr schema whoami --output json              # JSON Schema for the `whoami` response
xr schema blocked --output json             # JSON Schema for the `blocked` list
xr schema --envelope --output json          # the agent-native envelope (oneOf ok/dry_run/error)
xr schema --all --output json               # every schema in one document
```

The command name is a positional (`xr schema <name>`), matching the names `--list` prints. Output is a JSON Schema
2020-12 document. Feed it into a typed-codegen tool, drop it into a planning artifact, or diff it against an expected
shape.

`--list` is a two-column text table. Under `--output json` each row becomes a `{"message":"<name>  <type>"}` object
rather than structured fields, so the reliable way to read the names is the text form:

```bash
xr schema --list | awk '{print $1}'         # auth-apps-list auth-status block blocked … whoami envelope
```

The `--envelope` document is the one to read for the error contract: its `error` variant declares every key the runtime
can emit, including `next_step`, and its `reason` description is the closed set. Its `ok` variant describes the local
verbs only; API-backed successes carry no `status` key. See [output-envelope.md](output-envelope.md).

### 4. `xr validate`: schema check arbitrary JSON

```bash
xr read 1234567890 --output json | xr validate --schema post --output json
xr whoami --output json | xr validate --schema user --output json
xr search "x" --output json | xr validate --schema posts --output json
xr whoami --output json 2>&1 >/dev/null | xr validate --schema envelope --output json   # an error envelope
xr validate ./captured.json --schema envelope --output json
```

Reads JSON from a file argument or stdin (`-` or omitted argument both mean stdin). Emits `{"status":"ok","schema":
"<name>","valid":true}` when the input deserializes into the requested typed response, or a `validation-failed` envelope
with the field-level error. Use this to confirm a response shape after parsing it through a pipeline, or to gate a
script that expects a specific schema.

`--schema` accepts `post`, `posts`, `user`, `users`, `dm`, `dms`, `usage`, `credits`, `envelope`, `like`, `follow`,
`delete`, `repost`, `bookmark`, `mute`, `block`; anything else answers `reason: "unknown-schema"` with the list in
`known_schemas`. Without `--schema`, it auto-detects from the top-level shape.

Pick the schema by what came back: an API-backed success (`whoami`, `search`, `post`, …) validates against the verb's
schema; `envelope` accepts the `error`, `dry_run`, and local `ok` documents and **rejects** an API success, since that
document has no `status` key.

### 5. `xr auth status`: current token-store state

```bash
xr auth status --output json
xr auth status --output json | jaq -r '.apps[] | select(.default) | .name'
```

No API calls. Reads `~/.xurl` and answers `{"status":"ok","apps":[...]}`: one entry per registered app with `name`,
`client_id_hint`, `default`, `oauth2_users` (names only), `oauth1` / `bearer` presence booleans, `bearer_source`, and
the effective `redirect_uri` with its source. Read it through `.apps[]`; an empty store answers `"apps": []`. Use it
before any verb that needs a specific auth mode to confirm the right credential is staged. Full field list and the
exit-77 recovery recipe: [auth-modes.md](auth-modes.md).

## Adjacent helpers worth knowing

### `xr usage --output json` and `xr usage credits --output json`

Both call the X API. `usage` returns the project's post-cap usage with the daily breakdown; `usage credits` returns
the credits-based usage for pay-per-use projects. Useful when chasing a `reason: "rate-limited"` envelope. Each counts
against the app-level cap, so don't poll them from a tight loop.

### `xr version`

Prints `xr <semver>` (for example `xr 3.3.0`) as plain text under every output mode; there is no JSON form. No API
calls. Use it to confirm the bundle matches the binary; this bundle describes the 3.3.0 contract.

### `xr completions <shell>`

Emits a shell-completion script (bash / zsh / fish / elvish / powershell). Useful for users; not directly relevant to
agent work.

### `xr skill install <host>` and `xr skill update <host>`

Bundle management. `install` shallow-clones <https://github.com/brettdavies/xurl-rs-skill> into the host's canonical
skills directory; `update` removes that directory and clones again. Both honor `--dry-run` to preview the resolved `git
clone` command (`command_preview`) without spawning a process. Hosts: `claude_code`, `codex`, `cursor`, `factory`,
`kiro`, `opencode`.

`--all` answers one aggregated envelope for either verb:

```json
{
  "action": "skill-update",
  "status": "ok",
  "installations": [
    { "host": "claude_code", "status": "ok",      "exit_code": 0, "install_dir": "…", "command_preview": "git clone --depth 1 …", "destination_status": "non-empty-dir", "action": "skill-update" },
    { "host": "codex",       "status": "skipped", "exit_code": 0, "reason": "not-installed", "install_dir": "…", "command_preview": "…", "destination_status": "absent", "action": "skill-update" }
  ],
  "exit_code": 0
}
```

- `install --all` installs to every known host; `update --all` refreshes only hosts that already have an installation
  and reports the rest as `status: "skipped"`, `reason: "not-installed"`, exit code `0`.
- Scripts read the per-host records from `.installations[]`; the top-level `exit_code` is the worst one observed.
- A single-host call answers the per-host record alone, with the same fields.
- A failed removal during `update` answers `reason: "remove-failed"`, exit `1`, with no operating-system error text
  appended; `install` into an occupied path answers `destination-not-empty` or `destination-is-file`.

```bash
xr skill update --all --output json | jaq -r '.installations[] | "\(.host): \(.status) \(.reason // "")"'
```

## Workflow: verify before parsing

When you receive an `xr` response and intend to parse it, the safe pattern is exit code first, then the schema that
matches what that exit code implies:

```bash
EC=0
RESPONSE=$(xr whoami --output json 2>&1) || EC=$?
if [ "$EC" -ne 0 ]; then
  SCHEMA=envelope        # failure: the error envelope arrived on stderr
else
  SCHEMA=user            # success: the API document; pick the verb's schema
fi
printf '%s' "$RESPONSE" | xr validate --schema "$SCHEMA" --output json --quiet >/dev/null || {
  echo "Unexpected response shape" >&2
  printf '%s\n' "$RESPONSE" >&2
  exit 1
}
```

The `2>&1` matters: error envelopes go to stderr, so capturing stdout alone leaves `RESPONSE` empty on the exact path
you want to branch on. Two reads, one validate, one parse, at the cost of one extra round trip through the binary.
Worth it for any automation that branches on the response.

## What NOT to do

- **Don't reach for hand-written knowledge of `xr`'s flags** when `xr <cmd> --help` is one shell call away. The binary
  is the source of truth; this skill is the routing layer.
- **Don't memoize schema output**. Re-run `xr schema <name>` when you need the shape; the bundled schemas travel with
  the binary version, so the answer is always synchronized with what's actually installed.
- **Don't parse the text output of `xr` for automation**. Always pass `--output json` (or `XURL_OUTPUT=json`) and
  consume the structured envelope. Text mode is for humans; it can change without breaking a contract.
