# Agent flags: output, pagination, dry-run, env-var precedence

This file enumerates the global flags every `xr` command honors. The per-command flags are documented by `xr <cmd>
--help`.

## Output format

```bash
xr <cmd> --output <text|json|jsonl|ndjson|yaml|csv|tsv>
xr <cmd> --json                         # shorthand for --output json
xr <cmd> --jsonl                        # shorthand for --output jsonl
XURL_OUTPUT=json xr <cmd>               # env var equivalent
XURL_JSON=1 xr <cmd>                    # env var equivalent to --json
```

| Format   | What it emits                                                                                    |
| -------- | ------------------------------------------------------------------------------------------------ |
| `text`   | Human-readable, colored, default; the pretty JSON document when stdout is a pipe                 |
| `json`   | The document, pretty-printed (compact with `--raw`)                                              |
| `jsonl`  | The same document as `json`, pretty-printed; compact with `--raw`                                |
| `ndjson` | The same document, compact on one line                                                           |
| `yaml`   | YAML serialization of the JSON shape                                                             |
| `csv`    | Comma-separated, best-effort flattening of the top level; nested values are JSON-stringified     |
| `tsv`    | Tab-separated, same flattening                                                                   |

**No format splits a list response into one record per line.** `xr search … --output jsonl` prints the whole
`{"data":[…],"meta":{…}}` document exactly as `--output json` does, so `--output jsonl | jaq '.id'` answers `null`.
Per-record lines come from a filter on the document (`scripts/paginate.sh` does this across pages):

```bash
xr search "rustlang" -n 100 --output json | jaq -c '.data[]?'
```

Where `jsonl` / `ndjson` do matter is a streaming endpoint (`xr /2/tweets/search/stream --auth app`): every chunk the
stream delivers is printed as its own line under any structured format, and text mode adds `Connecting…` /
`End of stream` banners around them.

Formats outside this enum (e.g. `toml`, `xml`) are rejected at flag parsing: a clap usage error on stderr listing the
possible values, exit `2`, no envelope.

### `--raw`

```bash
xr <cmd> --raw                          # strip ANSI in text mode; compact JSON otherwise
XURL_RAW=1 xr <cmd>
```

Use `--raw` when piping `--output json` to another tool that doesn't want pretty-printing.

### Color control

```bash
xr <cmd> --color <auto|always|never>
XURL_COLOR=never xr <cmd>
NO_COLOR=1 xr <cmd>                     # always wins, per https://no-color.org
```

When stdout is not a TTY, color auto-strips even with `--color auto` (the default).

### TTY behavior

When stdout is not a TTY: color stripped, human-only banners suppressed, no prompts. Pipe-safe by construction, so
agents do not need any extra flag.

## Quiet, verbose, and tracing

```bash
xr <cmd> --quiet                        # XURL_QUIET=1; suppress non-essential output; errors still hit stderr
xr <cmd> --verbose                      # XURL_VERBOSE=1; log request and response details
xr <cmd> --trace                        # add X-B3-Flags trace header (per-request only, no env var)
```

`--quiet` plus `--output json` is the canonical agent pattern: structured success, structured error, no banner noise.

`--verbose` prints the request line, the response status, the response headers (including `x-rate-limit-*`), and the
raw body on stderr **in text mode only**; under any structured `--output` the diagnostics are suppressed so stderr
stays reserved for the error envelope. To capture a wire exchange, run the text-mode form and keep stdout separate:

```bash
xr whoami --verbose 2>wire.log >/dev/null
```

## Interactivity

```bash
xr <cmd> --no-interactive               # XURL_NO_INTERACTIVE=1; fail instead of prompt
xr <cmd> --no-pager                     # documented no-op; safe to pass unconditionally
```

`xr` never invokes `$PAGER`; `--no-pager` is advertised so agents can always pass it without the binary rejecting it.
The `--no-interactive` flag matters when running unattended; without it, `xr` may prompt for missing input on a TTY.
Destructive verbs (`delete`, `auth clear`, `auth apps remove`) answer `reason: "confirmation-required"`, exit `1`, when
they cannot prompt; pass `--force` after the user has confirmed. The gate runs before `--dry-run` is considered, so a
headless preflight of `delete` needs `--force` too.

## Timeouts

```bash
xr <cmd> --timeout 60                   # XURL_TIMEOUT=60; seconds, default 30
```

Bump for streaming endpoints or slow networks. Streaming verbs respect the timeout per chunk, not per stream.

## Dry-run

```bash
xr <write-verb> --dry-run --output json
XURL_DRY_RUN=1 xr <write-verb> --output json
```

**Honored by every write op**: `post`, `reply`, `quote`, `delete`, `like`, `unlike`, `repost`, `unrepost`, `bookmark`,
`unbookmark`, `follow`, `unfollow`, `block`, `unblock`, `mute`, `unmute`, `dm`, `media upload`. Read ops ignore
`--dry-run`.

Output shape:

- `--output text` → `Would <action> …` line on a TTY; the validated inputs as JSON when stdout is a pipe.
- `--output json` / `--output jsonl` → canonical `status: "dry_run"` envelope with `would_succeed`, `exit_code`, and a
  verb-specific payload (command name, body preview, target IDs).

Dry-run validates inputs only: no credential check, no filesystem check (`media upload` of a missing file still
answers `would_succeed: true`), and no bypass of a verb's own confirmation gate (`delete` needs `--force` even here).
See [output-envelope.md § Write-op preflight](output-envelope.md#write-op-preflight-status-dry_run).

## Pagination

X uses cursor-based pagination. Every list-style command returns a `meta.next_token` field; the next page is fetched by
re-running with `--cursor <token>`.

```bash
xr <list-cmd> --cursor <next_token>     # XURL_CURSOR=<token>
xr <list-cmd> --after <next_token>      # alias for --cursor (familiar from gh / kubectl)
xr <list-cmd> --page <n>                # NOT supported by X; returns reason: "unsupported-pagination"
```

Commands that thread `--cursor` through as `pagination_token`: `search`, `timeline`, `mentions`, `bookmarks`, `likes`,
`following`, `followers`, `muted`, `blocked`, `dms`. (The `--cursor` help text lists the first eight; `muted` and
`blocked` thread it the same way, verified on the 3.3.0 contract.)

### `--limit` and `-n/--max-results`

```bash
xr <list-cmd> --limit 50                # XURL_LIMIT=50; global, clamped to 1..=100
xr <list-cmd> -n 50                     # per-command, takes precedence when both set
```

Use `--limit` as a default cap across a script; override per call with `-n`. The default page size is 10. Every list
verb clamps the value to `1..=100`, except `search`, which the X API floors at 10: `xr search … -n 3` sends
`max_results=10`. Ask for fewer than 10 search results by filtering the page, not by lowering `-n`.

## Multi-app override

```bash
xr --app my-app <cmd>                   # XURL_APP=my-app
```

See [auth-modes.md](auth-modes.md) for multi-app management.

## Stdin

Commands that accept JSON input (currently `xr validate`) read from stdin when no file argument is given or `-` is
passed:

```bash
cat post.json | xr validate --schema post --output json
cat post.json | xr validate - --schema post --output json
xr validate ./post.json --schema post --output json
```

## Env-var precedence

Flags override env vars when both are set. The precedence rules `xr` documents explicitly:

- `NO_COLOR=1` always wins over `--color` / `XURL_COLOR`.
- For every other flag, the explicit CLI flag wins; the env var is the fallback.
- Booleans accept `1`, `true`, `yes`, `on` as truthy and `0`, `false`, `no`, `off`, empty as falsey.

The full env-var index is at the bottom of `xr --help`:

| Env var                                             | Equivalent flag                                                    |
| --------------------------------------------------- | ------------------------------------------------------------------ |
| `XURL_OUTPUT`                                       | `--output`                                                         |
| `XURL_JSON`                                         | `--json`                                                           |
| `XURL_JSONL`                                        | `--jsonl`                                                          |
| `XURL_RAW`                                          | `--raw`                                                            |
| `XURL_CURSOR`                                       | `--cursor`                                                         |
| `XURL_AFTER`                                        | `--after`                                                          |
| `XURL_PAGE`                                         | `--page`                                                           |
| `XURL_LIMIT`                                        | `--limit`                                                          |
| `XURL_DRY_RUN`                                      | `--dry-run`                                                        |
| `XURL_NO_INTERACTIVE`                               | `--no-interactive`                                                 |
| `XURL_NO_PAGER`                                     | `--no-pager`                                                       |
| `XURL_QUIET`                                        | `--quiet`                                                          |
| `XURL_VERBOSE`                                      | `--verbose`                                                        |
| `XURL_TIMEOUT`                                      | `--timeout`                                                        |
| `XURL_COLOR`                                        | `--color`                                                          |
| `XURL_APP`                                          | `--app`                                                            |
| `XURL_NO_BROWSER`                                   | `--no-browser` (auth only)                                         |
| `XURL_TOKEN_STORE`                                  | token-store file instead of `~/.xurl`                              |
| `XURL_BEARER_TOKEN`                                 | app-only bearer; wins over the stored bearer for the active app    |
| `CLIENT_ID`, `CLIENT_SECRET`                        | OAuth2 client credentials; win over the active app's stored values |
| `REDIRECT_URI`                                      | OAuth2 redirect URI override                                       |
| `AUTH_URL`, `TOKEN_URL`, `API_BASE_URL`, `INFO_URL` | endpoint overrides (test doubles, proxies)                         |

## Exit codes

| Code | Meaning                                                                                                          |
| ---- | ---------------------------------------------------------------------------------------------------------------- |
| 0    | success                                                                                                          |
| 1    | general error (also where `network-error` lands today)                                                           |
| 2    | invalid arguments (a clap usage message or an `invalid-args` envelope), unknown command, or auth-method mismatch |
| 3    | rate-limited (HTTP 429)                                                                                          |
| 4    | not found (HTTP 404)                                                                                             |
| 5    | `io` on file-access failures (a missing `media upload` path); `network-error` lands on 1                         |
| 77   | authentication required (`auth-required`, `token-store`); the envelope carries `next_step`                       |

When `--output json` is set, the same information is carried in the error envelope's `reason` field. Prefer the
envelope's `reason` over the exit code for branching in scripts, since it's a closed set and easier to pattern-match.
The reason → exit-code matrix and the exit-77 recipe are in [output-envelope.md](output-envelope.md).

## Canonical agent invocation

The shape that catches the most failure modes with the fewest flags:

```bash
xr <cmd> [args] \
  --output json \
  --no-interactive \
  --no-pager \
  --quiet
```

- `--output json`: structured success and error.
- `--no-interactive`: failures arrive as envelopes, not prompts.
- `--no-pager`: harmless, future-proof.
- `--quiet`: suppress human-only banners on stderr.

For writes, prepend `--dry-run` first, parse the dry-run envelope, then re-run without it.
