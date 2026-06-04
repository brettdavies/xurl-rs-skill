# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-06-04

### Added

- `VERSION` ships at `0.0.0`; bumped on first tagged release. by @brettdavies in
  [#1](https://github.com/brettdavies/xurl-rs-skill/pull/1)
- `cliff.toml` is the `git-cliff` config pointed at this repo, generating `CHANGELOG.md` from squash-merge commit
  history.
- `CHANGELOG.md` carries just the header and an empty `## [Unreleased]` section.
- Initial `xurl-rs` skill bundle for `xr` 1.3.0, containing `SKILL.md` (thin orchestrator that routes to the binary's
  own `xr examples` / `xr schema` / `xr validate` / `xr auth status` helpers), six references, four templates, and
  `getting-started.md`. Installs via `xr skill install <host>` into `~/.claude/skills/xurl-rs/` and equivalent paths on
  Codex / Cursor / Factory / Kiro / OpenCode. by @brettdavies in
  [#2](https://github.com/brettdavies/xurl-rs-skill/pull/2)
- `references/escalation.md` covers the ordered lookup (`xr --help` → `xr examples` → `xr schema` → `xr auth status` →
  companion `x-api` skill → docs.x.com → upstream issues → ask the user), iron rules with read-only-probe carve-outs,
  halt-vs-continue criteria, and four worked examples.
- `references/self-introspection.md` covers when and how to reach for `xr examples`, `xr schema --list / --command /
  --envelope / --all`, `xr validate`, `xr auth status`, and `xr usage`.
- `references/auth-modes.md` covers OAuth2 PKCE (browser + headless two-step), OAuth1, Bearer, the multi-app token store
  at `~/.xurl`, redirect-URI management, and verification via `xr auth status --output json`.
- `references/agent-flags.md` covers output formats (text / json / jsonl / ndjson / yaml / csv / tsv), pagination
  (`--cursor` / `--after` / `--page` / `--limit` / `-n`), dry-run, the env-var precedence matrix, exit codes, and the
  canonical agent invocation pattern.
- `references/output-envelope.md` covers the `ok` / `dry_run` / `error` envelope schema, the closed-set `reason` catalog
  with a reason-to-action lookup table, the exit-code mapping, and a pattern-match script template.
- `references/x-api-essentials.md` carries drift-resistant pointers into docs.x.com via `.md`-suffixed agent-friendly
  URLs, a companion `x-api` skill pointer, a 2026-06-03 verified-on date, and a stable-vs-API-side concepts split.
- `templates/oauth2-setup.md` ships first-time OAuth2 setup (browser and headless), multi-app registration,
  verification, and a troubleshooting matrix.
- `templates/post-reply-thread.md` ships single post, reply, quote, and threading-loop recipes (all gated by
  `scripts/dry-run-gate.sh`), plus media attachment, delete confirmation, and error parsing.
- `templates/search-and-process.md` ships an `xr search --output jsonl | jaq` pipeline, a cursor-pagination loop with
  bail-on-error, a search-then-enrich pattern, streaming endpoints, and output-format sketches. Leads with
  `scripts/paginate.sh`.
- `templates/media-upload.md` ships a `--media-type` / `--category` table, sync upload, the `--wait` flow, explicit
  polling via `xr media status`, attach-to-post, and an error-and-retry table.
- `getting-started.md` is a human-facing quickstart with an install matrix for all six supported hosts, a file-layout
  map, and companion `x-api` skill notes.
- `scripts/dry-run-gate.sh` is a deterministic wrapper that enforces `--dry-run` → `would_succeed=true && exit_code=0` →
  confirm → live for every `xr` write op. Refuses if the caller passes `--dry-run`, `--output`, `--json`, or `--jsonl`
  (the gate controls them) and refuses on non-TTY callers without `--yes`. Auto-detects `jaq` (preferred) or `jq`.
- `scripts/paginate.sh` is a cursor-pagination loop for any `xr` list-style verb. Streams `.data[]?` as compact JSONL on
  stdout, follows `meta.next_token`, bails on error envelopes, caps with `--max-pages` (default 20), supports `--cursor`
  resume and `--sleep` rate-limit pacing.
- `scripts/_common.sh` is a shared bash lib carrying the jq detection plus a PM-aware install-advice printer that
  detects `brew`, `cargo`, `pacman`, `dnf`, `nix-env`, `apt-get`, `zypper`, `yum`, `apk`, `port`, `pkg` and groups
  detected-on-system vs other options when neither `jaq` nor `jq` is on `PATH`.
- `scripts/README.md` is the contract for both scripts, listing exit codes, invocation patterns (install-path-relative
  and bundle-relative), and requirements.
- `evals/` ships five self-contained prompts (`eval-01-discover-and-auth`, `eval-02-search-and-process`,
  `eval-03-compose-dry-run` with a mandatory dry-run execution gate and marker tripwire,
  `eval-04-rate-limited-recovery`, `eval-05-tier-numbers-forced-escalation`) plus `evals/README.md` cataloging them.
  Every prompt body avoids naming the binary or this project so discovery is part of every test.

### Changed

- `README.md` swaps the bootstrap notice for the `xr skill install <host>` install matrix. by @brettdavies in
  [#2](https://github.com/brettdavies/xurl-rs-skill/pull/2)

### Documentation

- `CONTRIBUTING.md` is a stub: short routing and workflow guide that points at `AGENTS.md` (producer workflow) and
  `RELEASES.md` (branch/release model). Full guide will land alongside skill content. by @brettdavies in
  [#1](https://github.com/brettdavies/xurl-rs-skill/pull/1)
