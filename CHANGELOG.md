# Changelog

All notable changes to this project will be documented in this file.

## [0.3.0] - 2026-09-24

### Added

- Add the `broadcasts moderators list` / `add` / `remove` family to the guardrail, routing table, references, and
  templates: `add` / `remove` go through `scripts/dry-run-gate.sh` like every write verb and return
  `{"data":{"moderator_user_ids":[…]}}`; `list` is one unpaged GET run bare. by @brettdavies in
  [#20](https://github.com/brettdavies/xurl-rs-skill/pull/20)
- Add `evals/eval-07-broadcast-moderators.md`, a mutating-intent eval for the new family, and regression ids F9 / F10.
- Add `xr block`, `xr unblock`, `xr blocked`, and `xr muted` to the documented surface: read-op and write-op lists, the
  pagination verb list, the search-and-process list-verb table, the routing table, and the skill description. by
  @brettdavies in [#17](https://github.com/brettdavies/xurl-rs-skill/pull/17)
- Add `evals/eval-06-moderate-mentions.md`, which lists muted users through `scripts/paginate.sh` and preflights a
  block through the gate.

### Changed

- Change `scripts/paginate.sh` to exit 1 when a page hands back the cursor it was fetched with, so a verb that ignores
  `--cursor` no longer loops to `--max-pages`. by @brettdavies in
  [#20](https://github.com/brettdavies/xurl-rs-skill/pull/20)
- Change the reason catalog and exit-code matrix to the `xr 4.0.0` split: `forbidden` (403), `invalid-request` (400 /
  422), `server-error` (5xx), and `api-error` at exit 1; `network-error` at exit 5 for a request that got no answer;
  `enroll-app` only on a 403 that names enrollment.
- Change `xr version` guidance: `--output json` prints `{"name","version","xdk_rs"}` with no `status` key, `--verbose`
  names the linked `xdk-rs`; the bundle describes the 4.0.0 contract.
- Change `xr auth status` and `xr auth apps list` guidance to `{"status":"ok","apps":[...]}`, read through `.apps[]`,
  with an empty store answering `"apps": []`; every recipe and template that read the bare top-level array through
  `.[]` reads `.apps[]`. by @brettdavies in [#17](https://github.com/brettdavies/xurl-rs-skill/pull/17)
- Change `xr skill update --all` guidance to one aggregated envelope with `installations[]` that refreshes only hosts
  with an existing installation and reports the rest as `status: "skipped"`, `reason: "not-installed"`, at exit 0.

### Documentation

- Document the `dm` send confirmation, the `dm-event` and `moderators` schema names, `xr schema <verb>` answering
  `validation` on a verb with no typed response, tokens that predate the broadcast scopes, the `~/.xurl.lock` store
  lock, and the upstream repository's `crates/xurl-cli/` layout. by @brettdavies in
  [#20](https://github.com/brettdavies/xurl-rs-skill/pull/20)

**Full Changelog**: [v0.2.0...v0.3.0](https://github.com/brettdavies/xurl-rs-skill/compare/v0.2.0...v0.3.0)

## [0.2.0] - 2026-09-16

### Added

- `scripts/sync-dev-after-release.sh`, a release-backport tool that brings `dev` current with `main` after a tag
  publishes (overwrites `VERSION` with the released number, copies `CHANGELOG.md` verbatim from `origin/main`, opens a
  PR against `dev`). Idempotent on re-run. by @brettdavies in [#7](https://github.com/brettdavies/xurl-rs-skill/pull/7)
- Add `tests/contract.sh` and `tests/stub-api.py`, a hermetic harness that runs every documented invocation against a
  real `xr` build (`XR_BIN=/abs/path`) with a stub X API and asserts exit code, stream, body, and request log.
- Add a regression-fix table (F1–F8) to `evals/README.md` that every eval from eval-02 on names by id.

### Changed

- Document the per-app fields `xr auth status` and `xr auth apps list` emit (`name`, `client_id_hint`, `default`,
  `oauth2_users`, `oauth1`, `bearer`, `bearer_source`, `redirect_uri`, `redirect_uri_source`), and that both answer a
  bare top-level array read through `.[]`. by @brettdavies in
  [#13](https://github.com/brettdavies/xurl-rs-skill/pull/13)
- Add `next_step` to the error-envelope reference (`register-app` / `sign-in` / `select-app` / `inspect-store` /
  `enroll-app`, `command` vs `template`), the exit-77 recovery recipe with a script skeleton, and the closed-set reason
  catalog with the exit codes the binary emits (77 for `auth-required` / `token-store`).
- Document `status: "ok"` on the message-shaped auth verbs, and the `default` + `sign-in` `next_step` that `xr auth apps
  add` carries.
- Document `xr skill install --all` as one aggregated envelope with `installations[]`, `xr skill update --all` as one
  per-host document per known host, `command_preview` on update envelopes, and `remove-failed` on a failed removal.
- Change `xr version` guidance to `xr <semver>` and state the bundle describes the 3.2.0 release.
- Change `scripts/sync-dev-after-release.sh` to discover every path `main` and `dev` disagree about since the previous
  release tag, adopting release-prep paths and reporting contested ones, with `--dry-run`, `--only <path>`, and
  `--include-contested`. by @brettdavies in [#14](https://github.com/brettdavies/xurl-rs-skill/pull/14)
- Change `scripts/release/drift.sh` to fail its `.github/` gate only on changes `dev` carries that `main` never
  received.
- Change the output-contract reference to the four document kinds the binary emits: API-backed successes are the X API
  document with no `status` key; `status: "ok"` is local verbs only; `dry_run` on stdout; `error` on stderr with the
  exit code (`skill` verbs on stdout). by @brettdavies in [#17](https://github.com/brettdavies/xurl-rs-skill/pull/17)
- Change `--output jsonl` guidance: it prints the same whole document as `json`; per-record lines come from `jaq -c
  '.data[]?'`; only streaming endpoints emit one chunk per line.
- Change the page-size guidance: `1..=100`, default 10, `search` floors at 10; `-n` wins over `--limit`.
- Change `scripts/paginate.sh` and `scripts/dry-run-gate.sh` to capture stderr, name the envelope `reason` on refusal,
  accept statusless success documents, and pass the verb's exit code through.
- Change every docs.x.com URL that had moved (users, posts, lists, DMs, streams, media, usage, pagination, rate limits)
  and add the X API v2 `llms.txt` index and `AGENTS.md` to the escalation order.

### Fixed

- Fix invocations that did not run as written: `xr schema <name>` (not `--command`), `--schema post` (not `tweet`),
  `auth clear` selectors with `--force`, `auth apps redirect-uri get` / `set`, `auth default <APP> <USER>`, `--username`
  / `-u`, and `--force` on `delete` (including through `dry-run-gate.sh`). by @brettdavies in
  [#13](https://github.com/brettdavies/xurl-rs-skill/pull/13)
- Fix the `auth status` verification steps that expected `expires_at` and `refresh_token`; presence is reported through
  `oauth2_users`, and `xr` refreshes transparently.
- Fix the `--output toml` note: it is a clap usage error at exit 2, not an `invalid-args` envelope.
- Fix the update mechanism description: `xr skill update` removes the install directory and clones again.
- Fix the last `xr schema --command <name>` invocation in `references/x-api-essentials.md`.
- Fix `paginate.sh` exiting 0 on a failed page and refusing every real page (it required `status: "ok"`). by
  @brettdavies in [#17](https://github.com/brettdavies/xurl-rs-skill/pull/17)
- Fix the media id path (`.data.id`, not `.data.media_id`) in the media and post templates.
- Fix `delete` guidance: `--force` is needed for the `--dry-run` preflight off a TTY; the gate reports it.
- Fix `validate --schema envelope` recipes that a real success fails; validate API responses against the verb's schema
  (`user`, `posts`, …).
- Fix `--verbose` guidance: diagnostics print in text mode only; under `--output json` they are suppressed.
- Fix the schema count (35) and two scope names asserted from memory in the escalation reference.

### Documentation

- `AGENTS.md` gains a row describing the `docs/solutions/` symlink convention, the shared `brettdavies/solutions-docs`
  knowledge store, and when to consult it. The symlink itself is per-machine and gitignored. by @brettdavies in
  [#6](https://github.com/brettdavies/xurl-rs-skill/pull/6)
- `RELEASES.md` gains an `### After publish: sync dev with the release` subsection describing the
  `scripts/sync-dev-after-release.sh` invocation, the PR-based flow (cuts `chore/sync-dev-after-vX.Y.Z`, opens a PR
  rather than committing directly to dev), why the backport matters (without it, dev's `VERSION` and `CHANGELOG.md` stay
  frozen at pre-release state), and the script's idempotency. by @brettdavies in
  [#8](https://github.com/brettdavies/xurl-rs-skill/pull/8)

**Full Changelog**: [v0.1.0...v0.2.0](https://github.com/brettdavies/xurl-rs-skill/compare/v0.1.0...v0.2.0)

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
- `protect-main.json` bumps `required_approving_review_count` from `0` to `1` so PR authors cannot self-merge. Admin
  bypass preserved for break-glass; outside contributors are forced through review by construction. by @brettdavies in
  [#4](https://github.com/brettdavies/xurl-rs-skill/pull/4)
- `.github/CODEOWNERS` gains release-integrity, legal-hygiene, and workflow-doc paths (`cliff.toml`, `LICENSE-*`,
  `RELEASES.md`, `AGENTS.md`) on top of the existing governance paths (`scripts/**`, `.github/workflows/**`,
  `.github/rulesets/**`, `.github/CODEOWNERS`).

### Documentation

- `CONTRIBUTING.md` is a stub: short routing and workflow guide that points at `AGENTS.md` (producer workflow) and
  `RELEASES.md` (branch/release model). Full guide will land alongside skill content. by @brettdavies in
  [#1](https://github.com/brettdavies/xurl-rs-skill/pull/1)
