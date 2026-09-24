---
name: xurl-rs
description: Drive the X (Twitter) API from the command line via `xr`, the xurl-rs CLI. Use when the user wants to post or thread, reply, quote, delete, like, repost, bookmark, follow, mute, block, list who they have muted or blocked, send DMs, search recent posts, read a timeline or mentions, look up a user, upload media, stream filtered tweets, list, add, or remove the moderators of their broadcast chat, hit a raw `/2/...` endpoint, manage OAuth2 / OAuth1 / Bearer auth, register multiple X apps, inspect token state, check API usage or credits, or validate a tweet/user JSON payload against the typed response schema. Triggers on "post to X", "post to Twitter", "tweet from CLI", "X API call", "X CLI", "OAuth2 X", "xurl", "xr command", "search tweets", "send DM", "follow on X", "block on X", "mute on X", "broadcast moderators".
---

# xurl-rs (`xr`)

`xr` is a Rust CLI for the X (Twitter) API. It ships 34 high-level shortcut verbs, a raw curl-style mode for any
`/2/...` endpoint, OAuth1 / OAuth2-PKCE / Bearer auth with a multi-app token store at `~/.xurl`, chunked media upload,
streaming, typed JSON-schema responses, and typed error envelopes with a `next_step` an agent can act on. This bundle
describes the `xr 4.1.0` contract.

The binary self-introspects. Treat it as the source of truth: this skill routes you to the binary's helpers and provides
the workflow patterns that the binary can't describe on its own.

## Hard guardrail: production credentials

The `xr` binary on the user's machine is configured against **real X API credentials**, not a sandbox. Every write
operation (post / reply / quote / delete / like / unlike / repost / unrepost / bookmark / unbookmark / follow / unfollow
/ block / unblock / mute / unmute / dm / broadcasts moderators add / broadcasts moderators remove / media upload) hits
production state.

Before any write op:

1. Use `--dry-run` first to surface input validation errors and confirm intent. Every write verb emits a typed `status:
   "dry_run"` envelope when `--output json` and `--dry-run` are both set; check `would_succeed: true` and `exit_code:
   0`. Dry-run validates inputs only: not credentials, not the filesystem, and not the verb's own confirmation gate.
   Only the three verbs with no inverse (`delete`, `auth clear`, `auth apps remove`) gate themselves and need
   `--force` even for the preflight when there is no TTY; every other write verb, `block` and `mute` included, takes
   no `--force` (passing it is `invalid-args`).
2. Confirm scope with the user before issuing the live call when the action is destructive (`delete`, `block`,
   `unfollow`, `dm`, `post` to anything besides a test thread the user already named).
3. Prefer `--output json` with `--no-interactive` so failures arrive as structured envelopes you can act on.

Read ops (`read`, `search`, `whoami`, `user`, `timeline`, `mentions`, `bookmarks`, `likes`, `following`, `followers`,
`muted`, `blocked`, `dms`, `broadcasts moderators list`, `usage`, `usage credits`, `media status`, `auth status`,
`schema`, `validate`, `examples`, `version`) ignore `--dry-run` and are safe to run without confirmation.

## Quick start: let the binary teach you

The binary ships five self-introspection commands. Reach for them before reading anything in `references/`:

```bash
xr examples                          # curated invocation gallery, ~160 lines, every major workflow
xr <command> --help                  # 3-5 examples per command + full flag matrix
xr schema --list                     # 42 typed response shapes, one per command
xr schema post --output json         # JSON Schema for a single response type
xr schema --envelope --output json   # the ok / dry_run / error envelope variants and every error key
xr auth status --output json         # {"status":"ok","apps":[...]}; read it through .apps[]
```

For full read-only-probes-are-always-safe rules, see
[references/self-introspection.md](references/self-introspection.md).

## Read the exit code, then the document

Under `--output json`, a **success is the X API document itself** on stdout (`data`, plus `meta` / `includes` / `errors`
when the API sent them; typed verbs print renamed post fields under the spec's current names, such as
`edit_history_post_ids` and `repost_count`) with **no `status` key**; only local verbs (`auth …`, `validate`, `skill …`)
add `status: "ok"`. A **failure** is a `status: "error"` envelope on **stderr** with a non-zero exit, a kebab-case
`reason`, an `exit_code`, and, when a recovery exists, a `next_step` object. An HTTP refusal is `rate-limited` (exit
`3`), `not-found` (`4`), `auth-required` (`77`), or one of `forbidden` / `invalid-request` / `server-error` /
`api-error` (all exit `1`); `network-error` (exit `5`) means the request never got an answer. Exit `77` means no usable
credential; its `next_step.action` is one of `register-app` / `sign-in` / `select-app` / `inspect-store`. Two more
actions ride on other reasons: `enroll-app` on a `forbidden` that names enrollment, and `show-help` on `unknown-command`
(run its `command`: it is the help of the nearest real command). A `command` is safe to run verbatim while a `template`
needs values only the user has. A newer `xr` can add a `reason` or an `action`, so every branch needs a default that
reads `message` and shows the user the step rather than acting on it:

```bash
xr auth status --output json                 # {"status":"ok","apps":[...]}; each entry carries client_id_hint and bearer
xr whoami --output json 2>&1 >/dev/null      # the failure itself, carrying next_step
```

Branch on the exit code first, then on `reason` and `next_step.action`; never guess a credential fix, and never treat a
missing `status` on a `0` exit as an error. Full contract, catalog, and the exit-77 recipe:
[references/output-envelope.md](references/output-envelope.md).

## Deterministic helpers (`scripts/`)

The bundle ships two shellcheck-clean scripts that encode the rules the references describe. Prefer them when you can:
they enforce mechanically what the prose only requests.

| Script                                                      | Use for                                                                                                                                                                                            |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/dry-run-gate.sh [--yes] -- xr <write-verb> [args]` | Every write op. Runs `--dry-run` preflight, refuses on `would_succeed: false` or an error envelope (naming its `reason`), prompts on TTY or honors `--yes`, then `exec`s the live call.            |
| `scripts/paginate.sh [--max-pages N] -- xr <list-verb>`     | Every cursor-paginated read (`search`, `timeline`, `mentions`, `bookmarks`, `likes`, `following`, `followers`, `muted`, `blocked`, `dms`). Streams `.data[]?` as JSONL, follows `meta.next_token`. |

Both auto-detect `jaq` (preferred) or `jq`. When neither is installed, they emit a PM-aware install advice ranked by
what's already on the system. Install path after `xr skill install claude_code` (or the host equivalent) is
`~/.claude/skills/xurl-rs/scripts/`. Full contract: [scripts/README.md](scripts/README.md).

## Routing table

| Task                                       | First action                                                                                  |
| ------------------------------------------ | --------------------------------------------------------------------------------------------- |
| User wants to authenticate                 | [templates/oauth2-setup.md](templates/oauth2-setup.md)                                        |
| User wants to post / reply / thread        | `scripts/dry-run-gate.sh` + [templates/post-reply-thread.md](templates/post-reply-thread.md)  |
| User wants to search and pipe to a tool    | `scripts/paginate.sh` + [templates/search-and-process.md](templates/search-and-process.md)    |
| User wants to attach media                 | [templates/media-upload.md](templates/media-upload.md)                                        |
| Block / mute someone, or list who is       | `scripts/dry-run-gate.sh -- xr block @user`; `scripts/paginate.sh -- xr muted` (or `blocked`) |
| Manage broadcast chat moderators           | `scripts/dry-run-gate.sh -- xr broadcasts moderators add @user`; `list` is unpaged, run bare  |
| Pick an auth mode for a one-off            | [references/auth-modes.md](references/auth-modes.md)                                          |
| Pick output format / pagination / dry-run  | [references/agent-flags.md](references/agent-flags.md)                                        |
| Parse a response or an error               | [references/output-envelope.md](references/output-envelope.md)                                |
| Look up X API endpoints / scopes / billing | [references/x-api-essentials.md](references/x-api-essentials.md)                              |
| Don't know what `xr` can do                | [references/self-introspection.md](references/self-introspection.md)                          |
| Stuck, what next?                          | [references/escalation.md](references/escalation.md)                                          |

## Iron rules

1. **Never invent X API endpoints, scopes, billing tiers, or rate-limit numbers.** They change. See
   [references/escalation.md](references/escalation.md) for the lookup order.
2. **Never run a live write op without confirming scope with the user first**, OR without a successful `--dry-run` pass
   against the exact same flags first.
3. **Never paste credentials into chat, commits, PR bodies, or shell history.** Pass secrets through env vars
   (`XURL_BEARER_TOKEN`, `--client-secret "$(op read op://...)"`); never inline them.
4. **Read-only probes are always fine**: `xr --help`, `xr <cmd> --help`, `xr examples`, `xr schema ...`, `xr validate <
   file.json`, `xr auth status`, `xr version` (`--output json` for `{name, version, xdk_rs}`), `xr usage`, `xr usage
   credits`. No confirmation needed.

## Common flag patterns to apply across calls

- `--output json` (or `XURL_OUTPUT=json`): machine-readable on every command. `--output jsonl` prints the same whole
  document, not one record per line; get per-record lines with `jaq -c '.data[]?'` (or `scripts/paginate.sh`).
- `--no-interactive`: fail with a structured envelope instead of prompting.
- `--no-pager`: documented no-op, safe to always pass.
- `--quiet`: suppress human-only banners (errors still go to stderr).
- `--timeout 30` (the default): bump for streaming / slow networks.
- `-n <1..100>` / `--limit`: page size for list verbs (`search` floors at 10, the API's minimum); `--cursor <token>`
  from `meta.next_token` for the next page.

Full agent-flag matrix and env-var precedence: [references/agent-flags.md](references/agent-flags.md).

## Verifying the install

```bash
xr version                                   # prints "xr 4.1.0"; this bundle describes the 4.1.0 contract
xr version --output json | jaq -r '.version' # the same, machine-readable; .xdk_rs is the linked library version
xr --help                                    # full surface
xr whoam --output json 2>&1 | jaq -r '.next_step.action'   # "show-help" on 4.1.0 and later
xr auth status --output json | jaq -r '.apps[].name'       # which apps are registered
```

`xr` versions its contract by SemVer: a patch release only fixes, a minor release only adds, and a major release is
the only one that removes, renames, or retypes a command, exit code, or structured-output field (text-mode output is not
part of the contract). A newer `4.x` therefore keeps everything this bundle documents; what it adds reaches you as an
unrecognized `reason`, `action`, or key, which the default branches above absorb.

An older binary does not. On `xr 4.0.x`, an `unknown-command` envelope carries `suggestion` but no `next_step`, and
typed output prints X's legacy post field names (`edit_history_tweet_ids`, `retweet_count`) where X sends them. On
`xr 3.x`, `auth status` / `auth apps list` answer a bare top-level array (read `.[]` instead of `.apps[]`), `block` /
`unblock` / `blocked` / `muted` and the `broadcasts` family do not exist (`unknown-command`), every non-401/404/429 HTTP
failure is `network-error` at exit `1`, and `xr version` has no structured form. Upgrade (`brew upgrade xurl-rs`, or
<https://github.com/brettdavies/xurl-rs/releases>) rather than adapting the calls.

If `xr` is not on `$PATH`, install it from <https://github.com/brettdavies/xurl-rs/releases>, or refresh this bundle
with `xr skill update claude_code` (or whichever host; `xr skill update --all` refreshes every host that already has an
installation and skips the rest).

## Reference index

- [references/escalation.md](references/escalation.md): when stuck, lookup order, iron rules, halt-vs-continue, worked
  examples.
- [references/self-introspection.md](references/self-introspection.md): let the binary teach you (`examples`, `schema`,
  `validate`, `usage`).
- [references/auth-modes.md](references/auth-modes.md): OAuth2 PKCE (browser + headless), OAuth1, Bearer, multi-app
  token store, the `auth status` `apps` shape, what to do on exit 77.
- [references/agent-flags.md](references/agent-flags.md): output formats (and what `jsonl` really emits), pagination and
  clamps, dry-run, verbose, env-var precedence, exit codes.
- [references/output-envelope.md](references/output-envelope.md): the four document kinds (API document / `ok` /
  `dry_run` / `error`), the reason catalog (including the four HTTP-refusal reasons and `network-error` at exit `5`),
  `next_step` with `show-help` and the default-branch rule, typed output's post vocabulary, the exit-77 recipe,
  exit-code matrix, which schema validates which document.
- [references/x-api-essentials.md](references/x-api-essentials.md): drift-resistant pointers into the X API (auth
  scopes, tiers, rate limits, per-category doc URLs).

## Templates

- [templates/oauth2-setup.md](templates/oauth2-setup.md): first-time OAuth2 (browser or headless), verify with `xr auth
  status`.
- [templates/post-reply-thread.md](templates/post-reply-thread.md): compose, capture id, thread; leads with
  `scripts/dry-run-gate.sh`.
- [templates/search-and-process.md](templates/search-and-process.md): `xr search --output json | jaq -c '.data[]'`;
  leads with `scripts/paginate.sh`.
- [templates/media-upload.md](templates/media-upload.md): chunked upload, attach `--media-id` via the gate.

## Scripts

- [scripts/dry-run-gate.sh](scripts/dry-run-gate.sh): preflight → confirm → live wrapper for every `xr` write op.
- [scripts/paginate.sh](scripts/paginate.sh): cursor-pagination loop for any `xr` list-style verb.
- [scripts/README.md](scripts/README.md): full contract, exit codes, invocation patterns, jaq/jq fallback notes.

## Producer-side notes

This file is the *consumer* entry point and is loaded into the agent's context when the skill activates. *Producer-side*
notes for agents working **on** this bundle (release flow, branch model, CI, the contract harness that verifies every
claim above against a real binary) live in [AGENTS.md](AGENTS.md). Don't conflate the two.
