# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- `SKILL.md` consumer entry point with autodiscovery frontmatter, hard `--dry-run` guardrail for production credentials,
  and routing into references and templates.
- `references/escalation.md` — ordered lookup (`xr --help` → `xr examples` → `xr schema` → `xr auth status` → companion
  `x-api` skill → docs.x.com → upstream issues → ask the user), iron rules with read-only carve-outs, and worked
  examples.
- `references/self-introspection.md` — when and how to reach for `xr examples`, `xr schema
  --list/--command/--envelope/--all`, `xr validate`, `xr auth status`, `xr usage`.
- `references/auth-modes.md` — OAuth2 PKCE (browser + headless two-step), OAuth1, Bearer, multi-app token store at
  `~/.xurl`, redirect-URI management, verification via `xr auth status --output json`.
- `references/agent-flags.md` — output formats (text/json/jsonl/ndjson/yaml/csv/tsv), pagination
  (`--cursor`/`--after`/`--page`/`--limit`/`-n`), dry-run, env-var precedence matrix, exit codes, canonical agent
  invocation pattern.
- `references/output-envelope.md` — `ok` / `dry_run` / `error` envelope schema, closed-set reason catalog with
  reason-to-action lookup table, exit-code mapping, pattern-match script template.
- `references/x-api-essentials.md` — drift-resistant pointers into docs.x.com (with `.md` markdown suffix), companion
  `x-api` skill pointer, verified-on date, stable vs API-side concepts split.
- `templates/oauth2-setup.md` — first-time OAuth2 setup (browser and headless), multi-app registration, verification,
  troubleshooting matrix.
- `templates/post-reply-thread.md` — single post, reply, quote, threading loop with required `--dry-run` gate, media
  attachment, delete confirmation, error parsing.
- `templates/search-and-process.md` — `xr search --output jsonl | jaq` pipeline, cursor-pagination loop with
  bail-on-error, search-then-enrich pattern, streaming endpoints, output-format sketches.
- `templates/media-upload.md` — `--media-type` / `--category` table, sync upload, `--wait` flow, explicit polling via
  `xr media status`, attach to post, error-and-retry table.
- `getting-started.md` — human-facing quickstart with install matrix for all six supported hosts, file-layout map,
  companion `x-api` skill notes.
