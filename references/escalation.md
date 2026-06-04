# Escalation — when you're stuck

`xr` and this skill cover the common cases. Edge cases happen. This file names the lookup order so you don't guess.

## Lookup order

Walk these in order. Stop at the first one that answers the question.

1. **`xr <command> --help`** — the binary's own docs, always current with the installed version. The root `xr --help`
   ends with `ENVIRONMENT VARIABLES`, `INPUT FROM STDIN`, `EXIT CODES`, and `TTY behavior` sections. Most "how do I pass
   X?" questions resolve here.
2. **`xr examples`** — curated invocation gallery, ~120 lines, every major workflow with two-or-three lines per case.
   When the question is "what does the canonical pattern look like?", this is the answer.
3. **`xr schema --list --output json`** — 35 typed response shapes. When the question is "what does this response look
   like?" or "which fields can I rely on?", this is the answer.
4. **`xr schema --command <name> --output json`** — JSON Schema for one response type. Drop it into a generator or feed
   it back through `xr validate`.
5. **`xr schema --envelope --output json`** — the canonical agent-native envelope (`ok` / `dry_run` / `error`). When
   parsing automation output, match on `status` first.
6. **`xr auth status --output json`** — current registered apps, active user, token freshness. When OAuth feels broken,
   look here before re-running the flow.
7. **`xr usage --output json`** — current API caps and daily breakdown. When you hit `rate-limited`, this tells you
   whether you're at the daily wall or the per-window one.
8. **Companion skill `x-api`** (if installed) — endpoint reference for X API v2, scopes, billing tiers, rate-limit
   tables. Activates automatically when `xr` is in context.
9. **Official X docs** — every page supports markdown by appending `.md` to the URL. The index is
   <https://docs.x.com/llms.txt>. Use `defuddle` (or the agent's `fetch-web` skill) to clean MDX.
10. **Upstream issues** — <https://github.com/brettdavies/xurl-rs/issues>. Skill-bundle issues (stale references, wrong
    invocations, missing templates) **also** file here with a `[skill]` title prefix; this bundle's own issue tracker is
    disabled by design.
11. **Ask the user** — last resort, only when the answer requires user-side context (which thread to post in, which app
    to act as, whether to proceed with a destructive op).

## Iron rule — what to never invent

**Never invent X API endpoint paths, OAuth scopes, billing tiers, or rate-limit numbers.** They change. They are not in
`xr`'s scope to describe authoritatively. Always resolve via the lookup order above.

This rule has two carve-outs so it doesn't over-constrain:

- **Read-only probes are always fine** without asking the user: `xr --help`, `xr <cmd> --help`, `xr examples`, `xr
  schema ...`, `xr validate < file.json`, `xr auth status`, `xr usage`, `xr version`, fetching a docs page from
  `docs.x.com/.../<page>.md`. Run them as needed.
- **The CLI's own contract** (output formats, exit codes, env vars, dry-run envelope shape, pagination flags) is fine to
  cite from `xr --help` and this bundle. Those are stable per `xr` major version.

## Halt vs continue

**Halt and ask the user** when:

- The action is destructive (`delete`, `block`, `unfollow`, `dm` to anyone unfamiliar, `post` to anything besides a
  thread the user named).
- Authentication is missing for a verb that requires a user-scoped scope (Bearer can't post; OAuth2 PKCE needs the
  appropriate scope grants).
- The user's intent ambiguously maps to multiple X API endpoints (e.g., "show me my recent activity" — timeline,
  mentions, both?).
- Rate-limited (`reason: "rate-limited"`) and the agent does not know whether to wait or to pivot.

**Continue without asking** when:

- The action is read-only, the credentials are present, and the user's intent maps unambiguously to one endpoint.
- A `--dry-run` envelope has already returned `would_succeed: true` and the user has authorized the live call.
- The fix for a `validation` envelope is mechanically derivable (a typo'd field name, a missing required argument).

## Worked examples

### "How do I attach two images to a post?"

1. `xr post --help` → confirms `--media-id <MEDIA_IDS>` is repeatable.
2. `xr examples` → look under `MEDIA UPLOAD` for the upload-then-post pattern.
3. Run `xr media upload ./a.png --output json` to capture media_id A, again for B.
4. `xr post "text" --media-id <id_a> --media-id <id_b> --dry-run --output json` to confirm.
5. User confirms; run without `--dry-run`.

Done at step 1; the lookup short-circuits.

### "Why does my search return only 10 results when I asked for 50?"

1. `xr search --help` → `-n/--max-results` accepts 1-100.
2. Check whether the user passed `--limit` globally — the per-command `-n` wins when both are set, per `xr --help`'s
   `--limit` description.
3. If both are unset and the result count is still capped, the API itself may have been the cap. Check `xr usage
   --output json` to confirm we aren't tier-limited.
4. If still puzzled, the answer is at <https://docs.x.com/x-api/posts/search/introduction.md> — fetch it.

### "OAuth2 says token expired."

1. `xr auth status --output json` → look at the active user, `expires_at`, `refresh_token` presence.
2. If `refresh_token` is present, re-run any read-op once and `xr` will rotate automatically.
3. If absent, re-run the full flow: `xr auth oauth2` (browser) or `xr auth oauth2 --no-browser --step 1 / 2` (headless).
4. Re-verify with `xr auth status`.

### "What scope does `xr dm` need?"

1. `xr dm --help` → describes the CLI surface, not the scope.
2. `xr examples` → shows the invocation, not the scope.
3. Companion `x-api` skill → likely has DM scope details under `references/`.
4. Fall through to <https://docs.x.com/x-api/direct-messages/introduction.md>.

Do not guess the scope name. The agent that guesses `dm.write` when the real one is `dm.write.send` is the agent that
wastes a token refresh and an hour debugging an `auth-required` envelope.

## When to file a bug

A finding worth filing as `[skill]`-prefixed issue at <https://github.com/brettdavies/xurl-rs/issues/new/choose>:

- This bundle references a flag, command, or output that no longer matches the installed `xr`.
- A template's "before / after" example is wrong.
- A reference doc contradicts the binary's own help.

Not worth a bug:

- "I wish `xr` did X." That's a `xurl-rs` feature request, not a skill issue. Same tracker, different label.
- "This skill is too long." Open a discussion or PR against this bundle directly.
