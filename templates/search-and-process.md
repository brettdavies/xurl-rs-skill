# Template: search and process

Copy this template, fill the placeholders, and execute. Pipelines through `xr search` (or any other list-style verb)
into a typed processor like `jaq`. Read-only, so no `--dry-run` needed.

## Pre-flight

```bash
xr auth status --output json                 # .apps[]: search works on bearer: true OR an oauth2_users entry
xr usage --output json                       # check remaining caps; search counts against tweet caps
```

If only the Bearer is staged, force it:

```bash
xr search "<QUERY>" --auth app --output json
```

Search is one of the most rate-limited endpoints. Verify your `xr usage` daily breakdown before running a batch.

## Single page

```bash
xr search "<QUERY>" -n 50 --output json
```

The answer is the X API document, `{"data":[…],"meta":{"result_count":…,"next_token":…}}`, with no `status` key (see
[references/output-envelope.md](../references/output-envelope.md)). `-n` is the page size, `10..=100` for search (the
API's floor is 10; the other list verbs accept `1..=100`).

Capture and pipe:

```bash
xr search "<QUERY>" -n 50 --output json \
  | jaq '.data[] | {id, text, created_at, author_id}'
```

For one record per line (easier to stream and `jaq -c`), filter the document; no output mode splits it for you, and
`--output jsonl` prints the same whole document as `json`:

```bash
xr search "<QUERY>" -n 50 --output json \
  | jaq -c '.data[] | {id, text}'
```

## Cursor pagination, preferred path

The bundle ships a deterministic paginator that streams `.data[]?` records as compact JSONL on stdout, follows
`meta.next_token`, bails on error envelopes, and caps with `--max-pages`:

```bash
~/.claude/skills/xurl-rs/scripts/paginate.sh --max-pages 10 \
  -- xr search "<QUERY>" -n 100 \
  | jaq -c '{id, text, author_id}'
```

Options: `--max-pages N` (default 20), `--cursor TOKEN` (resume), `--sleep SECS` (pace against rate limits). Do NOT pass
`--cursor` / `--after` / `--page` / `--output` / `--json` / `--jsonl` / `--dry-run` to the verb; the script controls
them. Full contract: [scripts/README.md](../scripts/README.md).

The script lives at `~/.claude/skills/xurl-rs/scripts/paginate.sh` after `xr skill install claude_code` (or the
equivalent path on Codex / Cursor / Factory / Kiro / OpenCode). From the bundle directory, use `./scripts/paginate.sh`.

## Cursor pagination, manual path

When you need finer control (custom record filtering before stream, per-page hooks, different bail conditions), the
inline shape is:

```bash
#!/usr/bin/env bash
set -euo pipefail

QUERY="<QUERY>"
CURSOR=""
PAGE=0
MAX_PAGES=10

while [ "$PAGE" -lt "$MAX_PAGES" ]; do
  PAGE=$((PAGE + 1))
  EC=0
  if [ -z "$CURSOR" ]; then
    RESP=$(xr search "$QUERY" -n 100 --output json --quiet 2>&1) || EC=$?
  else
    RESP=$(xr search "$QUERY" -n 100 --cursor "$CURSOR" --output json --quiet 2>&1) || EC=$?
  fi

  # A failure is a non-zero exit with the error envelope (captured via 2>&1):
  # 3 rate-limited, 77 auth-required, 5 network-error, 1 for an API refusal.
  if [ "$EC" -ne 0 ]; then
    printf 'Page %d failed (%s): %s\n' "$PAGE" \
      "$(printf '%s' "$RESP" | jaq -r '.reason // "usage"')" "$RESP" >&2
    exit "$EC"
  fi

  # Stream this page's records. A success has no status key; .data[] is the page.
  printf '%s' "$RESP" | jaq -c '.data[]?'

  # Continue or stop.
  CURSOR=$(printf '%s' "$RESP" | jaq -r '.meta.next_token // empty')
  [ -n "$CURSOR" ] || break
done
```

Notes:

- `--cursor` and `--after` are the same flag (alias); `--page` is intentionally rejected because X does not support
  offset pagination; it returns `reason: "unsupported-pagination"`.
- Cap your loop with `MAX_PAGES` to avoid burning tweet caps on a runaway query.
- Sleep between pages if you start hitting `reason: "rate-limited"`.

## Pattern: search, then enrich

Common workflow: search returns tweet IDs and a sparse author payload; you want the full author profile per tweet. Group
authors, fetch once, join in memory:

```bash
#!/usr/bin/env bash
set -euo pipefail

QUERY="<QUERY>"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

xr search "$QUERY" -n 100 --output json --quiet \
  | jaq -c '.data[] | {tweet_id: .id, author_id, text}' \
  > "$TMP/tweets.jsonl"

# Unique author IDs.
jaq -r '.author_id' < "$TMP/tweets.jsonl" | sort -u > "$TMP/author_ids.txt"

# Fetch each author once.
while read -r AUTHOR_ID; do
  xr /2/users/"$AUTHOR_ID" --output json --quiet \
    | jaq -c '{id: .data.id, username: .data.username, name: .data.name}'
done < "$TMP/author_ids.txt" > "$TMP/authors.jsonl"

# Join (one-shot via jaq -s, two streams).
jaq -s --slurpfile authors "$TMP/authors.jsonl" '
  . as $tweets
  | $authors[0] | INDEX(.id) as $author_index
  | $tweets[] | . + { author: $author_index[.author_id] }
' < "$TMP/tweets.jsonl"
```

## Other list-style verbs

The same cursor-pagination loop works for every list-style verb:

| Verb        | Use                  |
| ----------- | -------------------- |
| `timeline`  | Your home timeline   |
| `mentions`  | Posts mentioning you |
| `bookmarks` | Your bookmarks       |
| `likes`     | Your liked posts     |
| `following` | Users you follow     |
| `followers` | Users following you  |
| `muted`     | Users you have muted |
| `blocked`   | Users you blocked    |
| `dms`       | Recent DM events     |

Substitute the verb in the loop above; the `--cursor` plumbing is identical. Confirm per-verb flags with `xr <verb>
--help`.

`xr broadcasts moderators list` is **not** in this table: it sends one `GET /2/broadcasts/chat/moderators`, ignores
`--cursor` and `--limit`, and has no `-n`, so run it directly (`xr broadcasts moderators list --output json | jaq -c
'.data[]?'`) rather than through the loop or `scripts/paginate.sh`.

## Streaming endpoints

For live filtered streams, use raw mode with `--output jsonl`; a streaming endpoint is the one case where every
chunk arrives on its own line (text mode adds `Connecting…` / `End of stream` banners around them):

```bash
xr /2/tweets/search/stream --auth app --output jsonl \
  | jaq -c '{id: .data.id, text: .data.text}'
```

Streaming requires app-auth (Bearer). The stream stays open until the connection ends or `xr --timeout` fires (bump it
with `XURL_TIMEOUT=600` for long streams).

## Schema verification

After capturing, verify the shape matches what `xr` claims. A search success is a `posts` document, not an envelope
(`--schema envelope` rejects it because it carries no `status` key):

```bash
xr search "<QUERY>" -n 10 --output json \
  | xr validate --schema posts --output json --quiet
```

Useful in CI when fixturing live captures.

## Output-format sketches

```bash
xr search "<QUERY>" -n 10 --output text         # human-readable table on a TTY; the JSON document when piped
xr search "<QUERY>" -n 10 --output json         # the document, pretty-printed
xr search "<QUERY>" -n 10 --output json --raw   # the document, compact, one line
xr search "<QUERY>" -n 10 --output jsonl        # identical to json for a list response
xr search "<QUERY>" -n 10 --output ndjson       # identical to json --raw
xr search "<QUERY>" -n 10 --output yaml         # YAML serialization
xr search "<QUERY>" -n 10 --output csv          # flat CSV: data and meta as JSON-stringified cells
xr search "<QUERY>" -n 10 --output tsv          # flat TSV
```

`csv` and `tsv` flatten only the top level, so `data` arrives as one JSON-stringified cell. Use `json` plus a `jaq`
filter for anything beyond a quick scan.
