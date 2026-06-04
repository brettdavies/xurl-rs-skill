# Self-introspection — let the binary teach you

`xr 1.3.0` is designed for agents. It ships five read-only commands that describe its own surface, schemas, and runtime
state. Reach for them before reading anything else. They are always safe to run — no credentials needed for most, no API
calls for any except `auth status` (which only inspects the local token store).

## The five helpers

### 1. `xr examples` — curated invocation gallery

```bash
xr examples
```

Plain-text gallery organized by use case: AUTHENTICATE, POST AND READ, MANAGE SOCIAL GRAPH, INSPECT YOUR ACCOUNT, DIRECT
MESSAGES, MEDIA UPLOAD, RAW MODE, INSPECT SCHEMAS, MULTI-APP, ENVIRONMENT VARIABLE PRECEDENCE. About 120 lines. Each
command appears with two or three canonical invocations (text mode, then `--output json`, sometimes piped to `jaq`).
This is the fastest way to learn the shape of any workflow.

### 2. `xr <command> --help` — per-command flag matrix and examples

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

### 3. `xr schema` — typed response shapes

```bash
xr schema --list --output json              # list all 35 schemas + their Rust types
xr schema --command post --output json      # JSON Schema for the `post` response
xr schema --command tweet --output json     # JSON Schema for the Tweet type itself
xr schema --envelope --output json          # the agent-native envelope (oneOf ok/dry_run/error)
xr schema --all --output json               # every schema in one document
```

Output is a JSON Schema 2020-12 document. Feed it into a typed-codegen tool, drop it into a planning artifact, or diff
it against an expected shape.

Without `--output json`, the schema commands emit a human-readable table — fine for scanning, not for parsing.

### 4. `xr validate` — schema check arbitrary JSON

```bash
xr read 1234567890 --output json | xr validate --schema tweet --output json
cat captured.json | xr validate --schema envelope --output json
xr validate ./captured.json --schema envelope --output json
```

Reads JSON from a file argument or stdin (`-` or omitted argument both mean stdin). Emits an `ok` envelope when the
input deserializes into the requested typed response, or a `validation-failed` envelope with the field-level error. Use
this to confirm a response shape after parsing it through a pipeline, or to gate a script that expects a specific
schema.

Without `--schema`, it auto-detects from the top-level shape.

### 5. `xr auth status` — current token-store state

```bash
xr auth status --output json
```

No API calls. Reads `~/.xurl` and reports: registered apps, active default app, registered users per app, token type
(OAuth1 / OAuth2-PKCE / Bearer), `expires_at` timestamps, refresh-token presence. Use it before any verb that needs a
specific auth mode to confirm the right credential is staged.

## Adjacent helpers worth knowing

### `xr usage --output json`

Calls the X API. Returns the project's API usage (tweet caps, daily breakdown). Useful when chasing a `reason:
"rate-limited"` envelope. Counts against the app-level cap, so don't poll it from a tight loop.

### `xr version`

Prints `xr 1.3.0`. No flags, no API calls. Use it to confirm the bundle matches the binary.

### `xr completions <shell>`

Emits a shell-completion script (bash / zsh / fish / elvish / powershell). Useful for users; not directly relevant to
agent work.

### `xr skill install <host>` and `xr skill update <host>`

Bundle management: shallow-clones <https://github.com/brettdavies/xurl-rs-skill> into the host's canonical skills
directory. Honor `--dry-run` to preview the resolved `git clone` / `git pull --ff-only` command without spawning a
process. Use `--all` to install across every known host (claude_code, codex, cursor, factory, kiro, opencode).

## Workflow — verify before parsing

When you receive an `xr` response and intend to parse it, the safe pattern is:

```bash
RESPONSE=$(xr whoami --output json)
echo "$RESPONSE" | xr validate --schema envelope --output json --quiet || {
  echo "Unexpected response shape" >&2
  echo "$RESPONSE" >&2
  exit 1
}
```

Two reads, one validate, one parse — at the cost of one extra round trip through the binary. Worth it for any automation
that branches on the response.

## What NOT to do

- **Don't reach for hand-written knowledge of `xr`'s flags** when `xr <cmd> --help` is one shell call away. The binary
  is the source of truth; this skill is the routing layer.
- **Don't memoize schema output**. Re-run `xr schema --command X` when you need the shape — the bundled schemas travel
  with the binary version, so the answer is always synchronized with what's actually installed.
- **Don't parse the text output of `xr` for automation**. Always pass `--output json` (or `XURL_OUTPUT=json`) and
  consume the structured envelope. Text mode is for humans; it can change without breaking a contract.
