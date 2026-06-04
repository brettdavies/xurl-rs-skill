# scripts/

Consumer-side helper scripts that ride along on every `xr skill install <host>`. They live next to the bundled
`SKILL.md` at `~/.claude/skills/xurl-rs/scripts/` (and the equivalent path on Codex / Cursor / Factory / Kiro /
OpenCode) once installed.

Both scripts auto-detect [`jaq`](https://github.com/01mf02/jaq) (preferred) or `jq`. They are `#!/usr/bin/env bash`,
shellcheck-clean, and meant to be invoked from any working directory.

| Script            | Purpose                                                          | Exit codes                                                                                  |
| ----------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `dry-run-gate.sh` | Enforce `--dry-run` → confirm → live for any `xr` write op.      | 0 live OK · 1 dry-run reject · 2 usage · 3 non-TTY w/o `--yes` · 4 declined · * passthrough |
| `paginate.sh`     | Cursor-paginate any list-style verb; stream `.data[]?` as JSONL. | 0 done · 1 envelope error · 2 usage · * passthrough                                         |

## `dry-run-gate.sh`

```bash
~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh [--yes] -- xr <write-verb> [args...]
```

What it does:

1. Runs the verb with `--dry-run --output json --quiet` and parses the envelope.
2. Refuses unless `status=dry_run`, `would_succeed=true`, `exit_code=0`. Read ops (`status=ok`) are rejected with a
   "just run it directly" note. Error envelopes propagate.
3. On a TTY, prompts `[y/N]`. Off a TTY, requires `--yes` or refuses.
4. `exec`s the verb again with `--output json` (no `--dry-run`) so the response envelope lands on stdout.

Do NOT pass `--dry-run`, `--output`, `--json`, or `--jsonl` to the gated verb — the script controls them. The gate
refuses if they appear in args.

Examples:

```bash
# Interactive (TTY) — gate prompts before going live.
~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh -- xr post "Shipping today."

# Headless — caller has already obtained user confirmation.
RESP=$(~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh --yes -- xr reply 1234567890 "Congrats!")
ID=$(printf '%s' "$RESP" | "${JQ_BIN:-jaq}" -r '.data.id')   # jaq or jq
```

## `paginate.sh`

```bash
~/.claude/skills/xurl-rs/scripts/paginate.sh [--max-pages N] [--cursor TOKEN] [--sleep SECS] -- xr <list-verb> [args...]
```

What it does:

1. Calls the verb with `--output json --quiet`. Bails on error envelopes.
2. Streams `.data[]?` to stdout as compact JSONL — one record per line.
3. Reads `meta.next_token`. If empty, exits 0. Otherwise re-runs with `--cursor <token>` until `--max-pages`.
4. On `--max-pages` cap, exits 0 and prints the next cursor on stderr so you can resume.

Do NOT pass `--cursor`, `--after`, `--page`, `--output`, `--json`, `--jsonl`, or `--dry-run` to the verb — the script
controls them. The script refuses if they appear in args.

Defaults:

- `--max-pages 20` — safety cap to keep runaway queries from burning tweet caps.
- `--sleep 0` — no delay between pages. Bump on rate-limit risk.

Examples:

```bash
# 10 pages of search, JSONL on stdout, diagnostics on stderr.
~/.claude/skills/xurl-rs/scripts/paginate.sh --max-pages 10 -- xr search "rustlang" -n 100

# Resume from a known cursor.
~/.claude/skills/xurl-rs/scripts/paginate.sh --cursor "$TOKEN" -- xr timeline -n 100

# Avoid the rate-limit window.
~/.claude/skills/xurl-rs/scripts/paginate.sh --sleep 2 -- xr followers -n 100
```

## Local invocation (from the bundle directory)

When the bundle is checked out for development (not installed via `xr skill install`), invoke from the bundle root:

```bash
./scripts/dry-run-gate.sh --yes -- xr post "..."
./scripts/paginate.sh -- xr search "..."
```

## Requirements

- `bash` — `#!/usr/bin/env bash`, uses `[[ ]]` regex matching.
- [`jaq`](https://github.com/01mf02/jaq) (preferred) OR `jq`. Each script picks `jaq` when both are installed, falls
  back to `jq` when only `jq` is present, and refuses to run when neither is on `PATH`. The jq expressions used
  (`.status // ""`, `.would_succeed`, `.exit_code`, `.data[]?`, `.meta.next_token // ""`) are standard syntax that both
  binaries parse identically.
- `xr` — the [xurl-rs](https://github.com/brettdavies/xurl-rs) binary.
