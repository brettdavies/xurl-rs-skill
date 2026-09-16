# scripts/

Consumer-side helper scripts that ride along on every `xr skill install <host>`. They live next to the bundled
`SKILL.md` at `~/.claude/skills/xurl-rs/scripts/` (and the equivalent path on Codex / Cursor / Factory / Kiro /
OpenCode) once installed.

Both scripts auto-detect [`jaq`](https://github.com/01mf02/jaq) (preferred) or `jq`. They are `#!/usr/bin/env bash`,
shellcheck-clean, and meant to be invoked from any working directory.

| Script            | Purpose                                                          | Exit codes                                                                                  |
| ----------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `dry-run-gate.sh` | Enforce `--dry-run` → confirm → live for any `xr` write op.      | 0 live OK · 1 dry-run reject · 2 usage · 3 non-TTY w/o `--yes` · 4 declined · * passthrough |
| `paginate.sh`     | Cursor-paginate any list-style verb; stream `.data[]?` as JSONL. | 0 done · 1 stdout error/dry_run document · 2 usage · * xr's exit on a failed page           |

Both model the binary's streams: a success is the raw X API document on stdout (no `status` key), a failure is an
error envelope on stderr with a non-zero exit. Each script captures stderr during its own calls so a refusal names the
`reason`, and passes the verb's exit code through when the verb fails. See
[references/output-envelope.md](../references/output-envelope.md) for the contract they encode.

## `dry-run-gate.sh`

```bash
~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh [--yes] -- xr <write-verb> [args...]
```

What it does:

1. Runs the verb with `--dry-run --output json --quiet`, capturing stderr, and parses the envelope.
2. Refuses unless `status=dry_run`, `would_succeed=true`, `exit_code=0`. A read op (which ignores `--dry-run` and
   answers its document with no `status`, or `status=ok` for a local verb) is rejected with a "run it directly" note
   at exit `2`. A non-zero preflight exit is reported with the envelope's `reason` at exit `1`; when that reason is
   `confirmation-required`, the message says to pass `--force`.
3. Echoes the accepted `dry_run` envelope on **stderr** (stdout is reserved for the live response), so capture
   `2>&1` when you want to keep it. On a TTY, prompts `[y/N]`. Off a TTY, requires `--yes` or refuses at exit `3`.
4. `exec`s the verb again with `--output json` (no `--dry-run`): the API document lands on stdout, a failure envelope
   on stderr, and the verb's exit code is the gate's.

Do NOT pass `--dry-run`, `--output`, `--json`, or `--jsonl` to the gated verb; the script controls them. The gate
refuses if they appear in args. DO pass `--force` for `delete`, `auth clear`, and `auth apps remove`: the binary's own
confirmation gate runs before `--dry-run`, so without it the preflight itself is refused. The gate is the
confirmation step.

Examples:

```bash
# Interactive (TTY): gate prompts before going live.
~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh -- xr post "Shipping today."

# Headless: caller has already obtained user confirmation.
RESP=$(~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh --yes -- xr reply 1234567890 "Congrats!")
ID=$(printf '%s' "$RESP" | "${JQ_BIN:-jaq}" -r '.data.id')   # jaq or jq

# A verb with its own confirmation gate: --force travels through.
~/.claude/skills/xurl-rs/scripts/dry-run-gate.sh -- xr delete 1234567890 --force
```

## `paginate.sh`

```bash
~/.claude/skills/xurl-rs/scripts/paginate.sh [--max-pages N] [--cursor TOKEN] [--sleep SECS] -- xr <list-verb> [args...]
```

What it does:

1. Calls the verb with `--output json --quiet`, capturing stderr. A non-zero exit ends the loop with the envelope's
   `reason` on stderr and the verb's exit code (`3` for `rate-limited`, `77` for `auth-required`, …). A `status:
   "error"` or `status: "dry_run"` document on stdout ends it at exit `1`.
2. Streams `.data[]?` to stdout as compact JSONL, one record per line. A page is the raw API document; the script does
   not expect a `status` key.
3. Reads `meta.next_token`. If empty, exits 0. Otherwise re-runs with `--cursor <token>` until `--max-pages`.
4. On `--max-pages` cap, exits 0 and prints the next cursor on stderr so you can resume.

Do NOT pass `--cursor`, `--after`, `--page`, `--output`, `--json`, `--jsonl`, or `--dry-run` to the verb; the script
controls them. The script refuses if they appear in args.

Defaults:

- `--max-pages 20`: safety cap to keep runaway queries from burning tweet caps. A user-scoped list verb resolves
  `/2/users/me` before each page, so 20 pages of `timeline` or `followers` is up to 40 requests; `search` and `dms` cost
  one per page.
- `--sleep 0`: no delay between pages. Bump on rate-limit risk.

Examples:

```bash
# 10 pages of search, JSONL on stdout, diagnostics on stderr.
~/.claude/skills/xurl-rs/scripts/paginate.sh --max-pages 10 -- xr search "rustlang" -n 100

# Resume from a known cursor.
~/.claude/skills/xurl-rs/scripts/paginate.sh --cursor "$TOKEN" -- xr timeline -n 100

# Avoid the rate-limit window.
~/.claude/skills/xurl-rs/scripts/paginate.sh --sleep 2 -- xr followers -n 100

# Any list verb: timeline, mentions, bookmarks, likes, following, followers, dms.
~/.claude/skills/xurl-rs/scripts/paginate.sh --max-pages 5 -- xr likes -n 100
```

## Local invocation (from the bundle directory)

When the bundle is checked out for development (not installed via `xr skill install`), invoke from the bundle root:

```bash
./scripts/dry-run-gate.sh --yes -- xr post "..."
./scripts/paginate.sh -- xr search "..."
```

## Requirements

- `bash`: `#!/usr/bin/env bash`, uses `[[ ]]` regex matching.
- [`jaq`](https://github.com/01mf02/jaq) (preferred) OR `jq`. Each script picks `jaq` when both are installed, falls
  back to `jq` when only `jq` is present, and refuses to run when neither is on `PATH`. The jq expressions used
  (`.status // ""`, `.reason // ""`, `.would_succeed`, `.exit_code`, `.data[]?`, `.meta.next_token // ""`) are
  standard syntax that both binaries parse identically.
- `xr`: the [xurl-rs](https://github.com/brettdavies/xurl-rs) binary.
