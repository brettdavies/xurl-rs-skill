---
name: xurl-rs
description: Drive the X (Twitter) API from the command line via `xr`, the xurl-rs CLI. Use when the user wants to post or thread, reply, quote, delete, like, repost, bookmark, follow, mute, block, send DMs, search recent posts, read a timeline or mentions, look up a user, upload media, stream filtered tweets, hit a raw `/2/...` endpoint, manage OAuth2 / OAuth1 / Bearer auth, register multiple X apps, inspect token state, check API usage caps, or validate a tweet/user JSON payload against the typed response schema. Triggers on "post to X", "post to Twitter", "tweet from CLI", "X API call", "OAuth2 X", "xurl", "xr command", "search tweets", "send DM", "follow on X".
---

# xurl-rs (`xr`)

`xr` is a Rust CLI for the X (Twitter) API. It ships ~30 high-level shortcut commands, a raw curl-style mode for any
`/2/...` endpoint, OAuth1 / OAuth2-PKCE / Bearer auth with a multi-app token store at `~/.xurl`, chunked media upload,
streaming, typed JSON-schema responses, and an agent-native output envelope.

The binary self-introspects. Treat it as the source of truth: this skill routes you to the binary's helpers and provides
the workflow patterns that the binary can't describe on its own.

## Hard guardrail — production credentials

The `xr` binary on the user's machine is configured against **real X API credentials**, not a sandbox. Every write
operation (post / reply / quote / delete / like / unlike / repost / unrepost / bookmark / unbookmark / follow / unfollow
/ block / unblock / mute / unmute / dm / media upload) hits production state.

Before any write op:

1. Use `--dry-run` first to surface input validation errors and confirm intent. Every write verb emits a typed `status:
   "dry_run"` envelope when `--output json` and `--dry-run` are both set; check `would_succeed: true` and `exit_code:
   0`.
2. Confirm scope with the user before issuing the live call when the action is destructive (`delete`, `block`,
   `unfollow`, `dm`, `post` to anything besides a test thread the user already named).
3. Prefer `--output json` with `--no-interactive` so failures arrive as structured envelopes you can act on.

Read ops (`read`, `search`, `whoami`, `user`, `timeline`, `mentions`, `bookmarks`, `likes`, `following`, `followers`,
`dms`, `usage`, `auth status`, `schema`, `validate`, `examples`, `version`) ignore `--dry-run` and are safe to run
without confirmation.

## Quick start — let the binary teach you

The binary ships three self-introspection commands. Reach for them before reading anything in `references/`:

```bash
xr examples                          # curated invocation gallery, ~120 lines, every major workflow
xr <command> --help                  # 3-5 examples per command + full flag matrix
xr schema --list --output json       # 35 typed response shapes, one per command
xr schema --command post --output json   # JSON Schema for a single response type
xr schema --envelope --output json   # the canonical agent-native output envelope (ok / dry_run / error)
xr auth status --output json         # current auth state across registered apps
```

For full read-only-probes-are-always-safe rules, see
[references/self-introspection.md](references/self-introspection.md).

## Deterministic helpers (`scripts/`)

The bundle ships two shellcheck-clean scripts that encode the rules the references describe. Prefer them when you can:
they enforce mechanically what the prose only requests.

| Script                                                      | Use for                                                                                                                                      |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/dry-run-gate.sh [--yes] -- xr <write-verb> [args]` | Every write op. Runs `--dry-run` preflight, refuses on `would_succeed: false`, prompts on TTY or honors `--yes`, then `exec`s the live call. |
| `scripts/paginate.sh [--max-pages N] -- xr <list-verb>`     | Every cursor-paginated read. Streams `.data[]?` as compact JSONL, follows `meta.next_token`, caps at `--max-pages`.                          |

Both auto-detect `jaq` (preferred) or `jq`. When neither is installed, they emit a PM-aware install advice ranked by
what's already on the system. Install path after `xr skill install claude_code` (or the host equivalent) is
`~/.claude/skills/xurl-rs/scripts/`. Full contract: [scripts/README.md](scripts/README.md).

## Routing table

| Task                                       | First action                                                                                 |
| ------------------------------------------ | -------------------------------------------------------------------------------------------- |
| User wants to authenticate                 | [templates/oauth2-setup.md](templates/oauth2-setup.md)                                       |
| User wants to post / reply / thread        | `scripts/dry-run-gate.sh` + [templates/post-reply-thread.md](templates/post-reply-thread.md) |
| User wants to search and pipe to a tool    | `scripts/paginate.sh` + [templates/search-and-process.md](templates/search-and-process.md)   |
| User wants to attach media                 | [templates/media-upload.md](templates/media-upload.md)                                       |
| Pick an auth mode for a one-off            | [references/auth-modes.md](references/auth-modes.md)                                         |
| Pick output format / pagination / dry-run  | [references/agent-flags.md](references/agent-flags.md)                                       |
| Parse a response or an error               | [references/output-envelope.md](references/output-envelope.md)                               |
| Look up X API endpoints / scopes / billing | [references/x-api-essentials.md](references/x-api-essentials.md)                             |
| User asks about OpenClaw / TweetClaw       | [references/openclaw-companion.md](references/openclaw-companion.md)                         |
| Don't know what `xr` can do                | [references/self-introspection.md](references/self-introspection.md)                         |
| Stuck — what next?                         | [references/escalation.md](references/escalation.md)                                         |

## Iron rules

1. **Never invent X API endpoints, scopes, billing tiers, or rate-limit numbers.** They change. See
   [references/escalation.md](references/escalation.md) for the lookup order.
2. **Never run a live write op without confirming scope with the user first**, OR without a successful `--dry-run` pass
   against the exact same flags first.
3. **Never paste credentials into chat, commits, PR bodies, or shell history.** Pass secrets through env vars
   (`XURL_BEARER_TOKEN`, `--client-secret "$(op read op://...)"`) — never inline them.
4. **Read-only probes are always fine**: `xr --help`, `xr <cmd> --help`, `xr examples`, `xr schema ...`, `xr validate <
   file.json`, `xr auth status`, `xr version`, `xr usage`. No confirmation needed.

## Common flag patterns to apply across calls

- `--output json` (or `XURL_OUTPUT=json`) — machine-readable on every command.
- `--no-interactive` — fail with a structured envelope instead of prompting.
- `--no-pager` — documented no-op, safe to always pass.
- `--quiet` — suppress human-only banners (errors still go to stderr).
- `--timeout 30` (the default) — bump for streaming / slow networks.

Full agent-flag matrix and env-var precedence: [references/agent-flags.md](references/agent-flags.md).

## Verifying the install

```bash
xr version             # prints "xr 1.3.0"
xr --help              # full surface
xr auth status         # which apps and users are registered
```

If `xr` is not on `$PATH`, install it from <https://github.com/brettdavies/xurl-rs/releases>, or refresh this bundle
with `xr skill update claude_code` (or whichever host).

## Reference index

- [references/escalation.md](references/escalation.md) — when stuck: lookup order, iron rules, halt-vs-continue, worked
  examples.
- [references/self-introspection.md](references/self-introspection.md) — let the binary teach you (`examples`, `schema`,
  `validate`, `usage`).
- [references/auth-modes.md](references/auth-modes.md) — OAuth2 PKCE (browser + headless), OAuth1, Bearer, multi-app
  token store.
- [references/agent-flags.md](references/agent-flags.md) — output formats, pagination, dry-run, env-var precedence, exit
  codes.
- [references/output-envelope.md](references/output-envelope.md) — the `ok` / `dry_run` / `error` envelope, typed
  reasons, exit-code matrix.
- [references/x-api-essentials.md](references/x-api-essentials.md) — drift-resistant pointers into the X API (auth
  scopes, tiers, rate limits).
- [references/openclaw-companion.md](references/openclaw-companion.md) - when OpenClaw / TweetClaw is a companion
  workflow, not a replacement for `xr`.

## Templates

- [templates/oauth2-setup.md](templates/oauth2-setup.md) — first-time OAuth2 (browser or headless), verify with `xr auth
  status`.
- [templates/post-reply-thread.md](templates/post-reply-thread.md) — compose, capture id, thread; leads with
  `scripts/dry-run-gate.sh`.
- [templates/search-and-process.md](templates/search-and-process.md) — `xr search --output jsonl | jaq`; leads with
  `scripts/paginate.sh`.
- [templates/media-upload.md](templates/media-upload.md) — chunked upload, attach `--media-id` via the gate.

## Scripts

- [scripts/dry-run-gate.sh](scripts/dry-run-gate.sh) — preflight → confirm → live wrapper for every `xr` write op.
- [scripts/paginate.sh](scripts/paginate.sh) — cursor-pagination loop for any `xr` list-style verb.
- [scripts/README.md](scripts/README.md) — full contract, exit codes, invocation patterns, jaq/jq fallback notes.

## Producer-side notes

This file is the *consumer* entry point and is loaded into the agent's context when the skill activates. *Producer-side*
notes for agents working **on** this bundle (release flow, branch model, CI) live in [AGENTS.md](AGENTS.md). Don't
conflate the two.
