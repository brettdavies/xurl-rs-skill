# Template — search and process

Copy this template, fill the placeholders, and execute. Pipelines through `xr search` (or any other list-style verb)
into a typed processor like `jaq`. Read-only — no `--dry-run` needed.

## Pre-flight

```bash
xr auth status --output json                 # search works on Bearer OR OAuth2
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

Capture and pipe:

```bash
xr search "<QUERY>" -n 50 --output json \
  | jaq '.data[] | {id, text, created_at, author_id}'
```

For one-record-per-line (easier to stream and `jaq -c`):

```bash
xr search "<QUERY>" -n 50 --output jsonl \
  | jaq -c '{id, text}'
```

## Cursor pagination — preferred path

The bundle ships a deterministic paginator that streams `.data[]?` records as compact JSONL on stdout, follows
`meta.next_token`, bails on error envelopes, and caps with `--max-pages`:

```bash
~/.claude/skills/xurl-rs/scripts/paginate.sh --max-pages 10 \
  -- xr search "<QUERY>" -n 100 \
  | jaq -c '{id, text, author_id}'
```

Options: `--max-pages N` (default 20), `--cursor TOKEN` (resume), `--sleep SECS` (pace against rate limits). Do NOT pass
`--cursor` / `--after` / `--page` / `--output` / `--json` / `--jsonl` / `--dry-run` to the verb — the script controls
them. Full contract: [scripts/README.md](../scripts/README.md).

The script lives at `~/.claude/skills/xurl-rs/scripts/paginate.sh` after `xr skill install claude_code` (or the
equivalent path on Codex / Cursor / Factory / Kiro / OpenCode). From the bundle directory, use `./scripts/paginate.sh`.

## Cursor pagination — manual path

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
  if [ -z "$CURSOR" ]; then
    RESP=$(xr search "$QUERY" -n 100 --output json --quiet)
  else
    RESP=$(xr search "$QUERY" -n 100 --cursor "$CURSOR" --output json --quiet)
  fi

  # Bail on errors before parsing data.
  STATUS=$(printf '%s' "$RESP" | jaq -r '.status')
  if [ "$STATUS" != "ok" ]; then
    printf 'Page %d failed: %s\n' "$PAGE" "$RESP" >&2
    exit 1
  fi

  # Stream this page's records.
  printf '%s' "$RESP" | jaq -c '.data[]?'

  # Continue or stop.
  CURSOR=$(printf '%s' "$RESP" | jaq -r '.meta.next_token // empty')
  [ -n "$CURSOR" ] || break
done
```

Notes:

- `--cursor` and `--after` are the same flag (alias); `--page` is intentionally rejected because X does not support
  offset pagination — it returns `reason: "unsupported-pagination"`.
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

xr search "$QUERY" -n 100 --output jsonl --quiet \
  | jaq -c '{tweet_id: .id, author_id, text}' \
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
| `dms`       | Recent DM events     |

Substitute the verb in the loop above; the `--cursor` plumbing is identical. Confirm per-verb flags with `xr <verb>
--help`.

## Streaming endpoints

For live filtered streams, use raw mode with `--output jsonl` so each record arrives on its own line:

```bash
xr /2/tweets/search/stream --auth app --output jsonl \
  | jaq -c '{id: .data.id, text: .data.text}'
```

Streaming requires app-auth (Bearer). The stream stays open until the connection ends or `xr --timeout` fires (bump it
with `XURL_TIMEOUT=600` for long streams).

## Schema verification

After capturing, verify the shape matches what `xr` claims:

```bash
xr search "<QUERY>" -n 5 --output json \
  | xr validate --schema envelope --output json --quiet
```

Useful in CI when fixturing live captures.

## Output-format sketches

```bash
xr search "<QUERY>" -n 10 --output text         # human-readable table
xr search "<QUERY>" -n 10 --output json         # one envelope
xr search "<QUERY>" -n 10 --output jsonl        # one record per line
xr search "<QUERY>" -n 10 --output yaml         # YAML serialization
xr search "<QUERY>" -n 10 --output csv          # flat CSV (best-effort)
xr search "<QUERY>" -n 10 --output tsv          # flat TSV
```

`csv` and `tsv` flatten the top-level shape; nested arrays may not survive. Use `json` / `jsonl` for anything beyond a
quick scan.
