# AGENTS.md — xurl-rs-skill

Producer-side instructions for agents (Claude Code, Codex, Cursor, OpenCode) working **on** this skill bundle.
Consumer-side instructions (how an agent should *use* the bundle once installed) live in `SKILL.md`.

> **Status:** bootstrap. Expand each section below as the skill content is authored.

## Repository shape

| Path                 | Role                                                                              |
| -------------------- | --------------------------------------------------------------------------------- |
| `SKILL.md`           | Consumer-facing entry point. Loaded by the agent when the skill activates.        |
| `references/`        | Reference material an agent reads on demand. One topic per file; deterministic.   |
| `templates/`         | Starter prompts and task recipes that the agent copies into a target project.     |
| `getting-started.md` | Human-oriented quickstart that complements `SKILL.md`.                            |
| `scripts/`           | Producer-side tooling (lint, sync, release helpers). ShellCheck-clean.            |
| `docs/`              | Planning artifacts (brainstorms, plans, solutions, reviews). Blocked from `main`. |
| `.github/`           | Workflows, rulesets, CODEOWNERS, PR/issue templates.                              |

## Branch model

- `dev` — forever branch. Daily work lands here via `feat/*` / `fix/*` / `chore/*` PRs.
- `main` — forever branch. Receives only `release/*` PRs cut from `origin/main` with non-docs commits cherry-picked from
  `dev`. Engineering docs under `docs/plans/`, `docs/solutions/`, `docs/brainstorms/`, `docs/reviews/` are blocked on
  `main` by `guard-main-docs`.
- `release/*` — ephemeral. Auto-deleted on merge.

See [`RELEASES.md`](RELEASES.md) for the full release workflow.

## CI

| Workflow              | Triggers                    | What it checks                               |
| --------------------- | --------------------------- | -------------------------------------------- |
| `ci.yml`              | push + PR to `main` / `dev` | `markdownlint`, `shellcheck` on `./scripts/` |
| `guard-main-docs.yml` | PR to `main`                | Blocks engineering docs from reaching `main` |

## House rules

- **No AI attribution in commits or PR bodies.** No `Co-Authored-By: Claude`, no `Generated with` trailers.
- **Signed commits required** on `main` and `dev` (ruleset-enforced).
- **Squash merges only.** PR title becomes the commit title; PR body becomes the commit message.
- **Conventional Commits**: `type(scope): description`. Prefer `feat` / `fix` over `chore` for anything user-observable.
- **Pin third-party actions by SHA**, never mutable tag. Trailing comment names the version.
