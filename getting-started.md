# Getting started with the `xurl-rs` skill

This is the human-facing quickstart. The agent-facing entry point is [`SKILL.md`](SKILL.md); the producer-side notes for
working on this bundle are in [`AGENTS.md`](AGENTS.md).

## What this bundle is

A consumer-side skill bundle for `xr` (the `xr 4.2.0` contract), the Rust port of the Go xurl. The CLI lives at
<https://github.com/brettdavies/xurl-rs> (its reference is `crates/xurl-cli/README.md`; the Rust library beside it is
`xdk-rs`); this bundle teaches your coding agent how to drive it without inventing flags or trampling production
state. Every invocation the bundle documents is checked against a real `xr` build by
`tests/contract.sh` before a bundle pass ships (see [`AGENTS.md`](AGENTS.md)).

When the bundle is installed at `~/.claude/skills/xurl-rs/` (or the equivalent path on Codex / Cursor / Factory / Kiro /
OpenCode), Claude Code automatically reads the description in `SKILL.md` and pulls the rest of the files in on demand.

## Install

The `xr` binary ships its own bundle-installer:

```bash
xr skill install claude_code             # install for Claude Code
xr skill install codex                   # install for Codex
xr skill install --all                   # install across every known host
xr skill install claude_code --dry-run   # preview the git command without running it
```

Hosts and install paths:

| Host          | Install path                        |
| ------------- | ----------------------------------- |
| `claude_code` | `~/.claude/skills/xurl-rs`          |
| `codex`       | `~/.agents/skills/xurl-rs`          |
| `cursor`      | `~/.cursor/skills/xurl-rs`          |
| `factory`     | `~/.factory/skills/xurl-rs`         |
| `kiro`        | `~/.kiro/skills/xurl-rs`            |
| `opencode`    | `~/.config/opencode/skills/xurl-rs` |

A host's own config-directory variable moves its row: `CLAUDE_CONFIG_DIR` stands in for `~/.claude`, `KIRO_HOME` for
`~/.kiro`, and `OPENCODE_CONFIG_DIR` for `~/.config/opencode`. Otherwise `XURL_SKILL_HOME`, when set, stands in for `~`
in every row (useful for a sandbox or a test that must not touch your real home). Below that, `XDG_CONFIG_HOME` stands
in for `~/.config` in the `opencode` row. `--dry-run` prints the resolved path, so check it before the first install.

Codex also reads the older `~/.codex/skills/xurl-rs`. When a copy sits there, `xr skill install codex` leaves it and
says so (`legacy_install_dir` under `--output json`), so Codex sees two copies; `xr skill update codex` removes it and
installs at `~/.agents/skills/xurl-rs`.

Update in place:

```bash
xr skill update claude_code              # remove the install dir and clone fresh
xr skill update --all                    # refresh hosts with an install (an old ~/.codex copy counts)
```

Uninstall:

```bash
rm -rf ~/.claude/skills/xurl-rs          # or the equivalent host path
```

## First session

Once installed, the skill auto-activates the next time you ask Claude Code to do something X-API-flavored. Try:

> Post a draft tweet about my morning run.

Claude will route through `SKILL.md`, open [`templates/post-reply-thread.md`](templates/post-reply-thread.md), require a
`--dry-run` pass first, and ask for your confirmation before going live, because `xr` is configured against production
credentials by design.

To explore manually:

```bash
xr --help                    # full surface
xr examples                  # curated invocation gallery
xr <cmd> --help              # per-command flags + examples
xr schema --list             # every typed response shape
xr version --output json     # {"name":"xr","version":"<semver>","xdk_rs":"<semver>"}
xr auth status               # who's authenticated
```

## What's in this bundle

```text
xurl-rs-skill/
├── SKILL.md                              # consumer entry point (Claude reads this)
├── getting-started.md                    # this file
├── AGENTS.md                             # producer-side notes (for editors of this bundle)
├── references/
│   ├── escalation.md                     # when stuck: lookup order + iron rules
│   ├── self-introspection.md             # `xr examples`/`schema`/`validate`/`auth status`
│   ├── auth-modes.md                     # OAuth2 PKCE, OAuth1, Bearer, multi-app
│   ├── agent-flags.md                    # output, pagination, dry-run, env-var precedence
│   ├── output-envelope.md                # API document / `ok` / `dry_run` / `error` + reason catalog
│   └── x-api-essentials.md               # drift-resistant pointers into the X API docs
├── templates/
│   ├── oauth2-setup.md                   # first-time auth (browser + headless)
│   ├── post-reply-thread.md              # compose / capture id / thread
│   ├── search-and-process.md             # `xr search --output json | jaq -c '.data[]'`
│   └── media-upload.md                   # chunked upload, alt text, subtitles, attach to post
└── scripts/
    ├── dry-run-gate.sh                   # --dry-run → confirm → live, for every write op
    ├── paginate.sh                       # cursor loop for every list verb
    └── README.md                         # the two scripts' contract
```

## Companion: the `x-api` skill

This bundle is about **using** `xr`. For X API endpoint shapes, scope catalogs, and rate-limit tables, install the
separate `x-api` skill; it auto-loads alongside `xurl-rs`. The two are complementary:

- `xurl-rs` (this bundle): how to drive `xr`.
- `x-api`: what the X API itself offers.

If you don't have the `x-api` skill, fall through to <https://docs.x.com/> (append `.md` to any docs URL for
agent-friendly markdown; see [`references/x-api-essentials.md`](references/x-api-essentials.md)).

## Reporting issues

This repository's GitHub issue tracker is disabled. File everything (CLI bugs, skill-bundle bugs, template requests)
at the upstream `xurl-rs` repo:

➡️ **<https://github.com/brettdavies/xurl-rs/issues/new/choose>**

When the issue is specifically about this bundle, **prefix the title with `[skill]`** so it can be triaged correctly.
