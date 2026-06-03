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
- `scripts/dry-run-gate.sh` — deterministic wrapper that enforces `--dry-run` → `would_succeed=true && exit_code=0` →
  confirm → live for any `xr` write op. Refuses if the user passes `--dry-run`, `--output`, `--json`, or `--jsonl` (the
  gate controls them); refuses on non-TTY without `--yes`. Auto-detects `jaq` (preferred) or `jq`.
- `scripts/paginate.sh` — cursor-pagination loop for any `xr` list-style verb. Streams `.data[]?` as compact JSONL on
  stdout, follows `meta.next_token`, bails on error envelopes, caps with `--max-pages` (default 20), supports `--cursor`
  resume and `--sleep` rate-limit pacing.
- `scripts/_common.sh` — shared bash lib carrying the jq detection plus a PM-aware install-advice printer that detects
  `brew`, `cargo`, `pacman`, `dnf`, `nix-env`, `apt-get`, `zypper`, `yum`, `apk`, `port`, `pkg` and groups detected vs
  other options when neither `jaq` nor `jq` is on `PATH`.
- `scripts/README.md` — contract for both scripts, exit codes, invocation patterns (install-path-relative and
  bundle-relative), and requirements.
- `fixtures/bin/xr` — bash stub that emits envelope JSON from `XR_STUB_DRYRUN_BODY` / `XR_STUB_LIVE_BODY` env vars or
  cycles newline-separated envelopes from `XR_STUB_PAGES_BODIES` for multi-page paginate tests.
- `tests/run.sh` — fixture-driven test runner. 16 test cases covering: `dry-run-gate.sh` (accept-clean,
  reject-would-not-succeed, reject-read-op, reject-error, reject-forbidden-dry-run/output/json flags,
  refuse-non-TTY-without-yes, missing-args) and `paginate.sh` (single-page, multi-page-follows-cursor, bail-on-error,
  stop-at-max-pages, reject-forbidden-cursor/output flags, reject-bad-max-pages).
- `evals/eval-01-discover-and-auth.md` — discovery + auth-mode selection eval. Self-contained prompt.
- `evals/eval-02-search-and-process.md` — discovery + paginator-helper selection eval. Self-contained prompt.
- `evals/eval-03-compose-dry-run.md` — mutating-intent eval with mandatory dry-run execution gate, marker tripwire,
  automatic 0 on live-mutation evidence in `FINAL-REPORT.md`.
- `evals/eval-04-rate-limited-recovery.md` — envelope `reason` interpretation + recovery decision-tree eval.
- `evals/eval-05-tier-numbers-forced-escalation.md` — forced-escalation eval scoring the PROCESS (refuse to quote tier
  numbers from memory; name the canonical external source) over the answer.
- `evals/README.md` — eval catalog, workdir convention, grading method, iteration-loop rules.

### Changed

- `SKILL.md` routing table now leads with the scripts for write ops and paginated reads, with the templates as the
  fallback / deeper-knowledge path. New "Deterministic helpers" section in the body.
- `templates/post-reply-thread.md`, `templates/search-and-process.md`, and `templates/media-upload.md` now lead with the
  relevant script and document the manual path as a fallback.
- `README.md` drops the bootstrap notice and points at `xr skill install <host>` as the preferred install path.
- `AGENTS.md` scripts/ row reframed as consumer-side helpers (was "producer-side tooling"); added rows for the new
  `tests/`, `fixtures/`, and `evals/` directories.
- `.github/workflows/ci.yml` shellcheck job now lints `scripts/` + `tests/` + `fixtures/bin/` together; new
  `scripts-tests` job runs `bash tests/run.sh` end-to-end (no live API; ubuntu-latest's pre-installed `jq` is
  auto-detected by `_common.sh`).
