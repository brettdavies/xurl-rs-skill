# xurl-rs-skill

Claude Code skill bundle for [`xurl-rs`](https://github.com/brettdavies/xurl-rs) — the X (Twitter) CLI for agents.

> **Status:** bootstrap. Skill content (`SKILL.md`, `references/`, `templates/`, `getting-started.md`) is authored after
> this initial scaffold lands.

## What this is

A Claude Code (and Codex / Cursor / OpenCode) skill bundle that teaches an agent how to use `xurl-rs` against the X
(Twitter) API — authentication, requests, pagination, rate-limit handling, and common task templates.

## Install

Once published:

```bash
# Claude Code
mkdir -p ~/.claude/skills && \
  git clone https://github.com/brettdavies/xurl-rs-skill ~/.claude/skills/xurl-rs
```

## Layout

| Path                 | Purpose                                                                     |
| -------------------- | --------------------------------------------------------------------------- |
| `SKILL.md`           | Entry point Claude Code / Codex / Cursor load when the skill activates.     |
| `references/`        | Reference material the agent reads on demand (auth flows, endpoint shapes). |
| `templates/`         | Starter prompts and task recipes the agent can copy into a project.         |
| `getting-started.md` | Human-oriented quickstart.                                                  |
| `scripts/`           | Producer-side tooling (sync, lint, release helpers).                        |

## License

Dual-licensed under [MIT](LICENSE-MIT) and [Apache 2.0](LICENSE-APACHE) at your option.
