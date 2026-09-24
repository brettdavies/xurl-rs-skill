# Escalation: when you're stuck

`xr` and this skill cover the common cases. Edge cases happen. This file names the lookup order so you don't guess.

## Lookup order

Walk these in order. Stop at the first one that answers the question.

1. **`xr <command> --help`**: the binary's own docs, always current with the installed version. The root `xr --help`
   ends with `ENVIRONMENT VARIABLES`, `INPUT FROM STDIN`, `EXIT CODES`, and `TTY behavior` sections. Most "how do I pass
   X?" questions resolve here. A mistyped command answers `unknown-command` with a `show-help` `next_step`: its
   `command` is the right help page to read.
2. **`xr examples`**: curated invocation gallery, ~160 lines, every major workflow with two-or-three lines per case.
   When the question is "what does the canonical pattern look like?", this is the answer.
3. **`xr schema --list`**: 42 typed response shapes, one row per verb (`<name> <Rust type>`). When the question is "what
   does this response look like?" or "which fields can I rely on?", this is the answer. A verb with no typed response
   (`validate`, `skill`, `examples`, `version`, `auth`, `media`) answers `schema not available`.
4. **`xr schema <name> --output json`**: JSON Schema for one response type. Drop it into a generator or feed it back
   through `xr validate`.
5. **`xr schema --envelope --output json`**: the canonical agent-native envelope (`ok` / `dry_run` / `error`). When
   parsing automation output, read the exit code first: non-zero means an error envelope on stderr (`reason`, then
   `next_step`); zero with no `status` key means an API document on stdout, which is the normal success shape. See
   [output-envelope.md](output-envelope.md).
6. **`xr auth status --output json`**: `{"status":"ok","apps":[...]}` with the registered apps, which is default, which
   OAuth2 users and which credential kinds each holds. When OAuth feels broken, look here before re-running the flow.
   When a verb exits `77`, its own envelope's `next_step` already names the fix.
7. **`xr usage --output json`**: current API caps and daily breakdown. When you hit `rate-limited`, this tells you
   whether you're at the daily wall or the per-window one.
8. **Companion skill `x-api`** (if installed): endpoint reference for X API v2, scopes, billing tiers, rate-limit
   tables. Activates automatically when `xr` is in context.
9. **Official X docs**: every page supports markdown by appending `.md` to the URL. <https://docs.x.com/llms.txt> is a
   short index of nested indexes; the X API v2 reference index is <https://docs.x.com/x-api/llms.txt>, and
   <https://docs.x.com/AGENTS.md> carries X's own instructions for agents reading the docs. Use `defuddle` (or the
   agent's `fetch-web` skill) to clean MDX.
10. **Upstream repository**: the CLI reference is `crates/xurl-cli/README.md` and its changelog
    `crates/xurl-cli/CHANGELOG.md` in <https://github.com/brettdavies/xurl-rs> (the root README routes between the
    `xr` CLI and the `xdk-rs` Rust library; a Rust program that wants the X API embeds `xdk-rs`, not the CLI). Issues:
    <https://github.com/brettdavies/xurl-rs/issues>. Skill-bundle issues (stale references, wrong invocations, missing
    templates) **also** file here with a `[skill]` title prefix; this bundle's own issue tracker is disabled by design.
11. **Ask the user**: last resort, only when the answer requires user-side context (which thread to post in, which app
    to act as, whether to proceed with a destructive op).

## Iron rule: what to never invent

**Never invent X API endpoint paths, OAuth scopes, billing tiers, or rate-limit numbers.** They change. They are not in
`xr`'s scope to describe authoritatively. Always resolve via the lookup order above.

This rule has two carve-outs so it doesn't over-constrain:

- **Read-only probes are always fine** without asking the user: `xr --help`, `xr <cmd> --help`, `xr examples`, `xr
  schema ...`, `xr validate < file.json`, `xr auth status`, `xr usage`, `xr usage credits`, `xr version`, fetching a
  docs page from `docs.x.com/.../<page>.md`. Run them as needed.
- **The CLI's own contract** (output formats, exit codes, env vars, dry-run envelope shape, pagination flags) is fine to
  cite from `xr --help` and this bundle. Those are stable per `xr` major version.

## Halt vs continue

**Halt and ask the user** when:

- The action is destructive (`delete`, `block`, `unfollow`, `dm` to anyone unfamiliar, `post` to anything besides a
  thread the user named).
- Authentication is missing for a verb that requires a user-scoped scope (Bearer can't post; OAuth2 PKCE needs the
  appropriate scope grants).
- The user's intent ambiguously maps to multiple X API endpoints (e.g., "show me my recent activity": timeline,
  mentions, both?).
- Rate-limited (`reason: "rate-limited"`) and the agent does not know whether to wait or to pivot.

**Continue without asking** when:

- The action is read-only, the credentials are present, and the user's intent maps unambiguously to one endpoint.
- A `--dry-run` envelope has already returned `would_succeed: true` and the user has authorized the live call.
- The fix for a `validation` envelope is mechanically derivable (a typo'd field name, a missing required argument).
- An envelope carries `next_step.action: "show-help"`: its `command` is a help page, read-only, so run it and retry the
  corrected invocation.

## Worked examples

### "How do I attach two images to a post?"

1. `xr post --help` → confirms `--media-id <MEDIA_IDS>` is repeatable.
2. `xr examples` → look under `MEDIA UPLOAD` for the upload-then-post pattern.
3. Run `xr media upload ./a.png --output json` to capture media_id A, again for B.
4. `xr post "text" --media-id <id_a> --media-id <id_b> --dry-run --output json` to confirm.
5. User confirms; run without `--dry-run`.

Done at step 1; the lookup short-circuits.

### "Why does my search return only 10 results when I asked for 50?"

1. `xr search --help` → `-n/--max-results` is the per-call page size; the default is 10 when neither `-n` nor `--limit`
   is set.
2. Check whether the user passed `--limit` globally; the per-command `-n` wins when both are set, per `xr --help`'s
   `--limit` description. (`search` also floors the value at 10, the X API's minimum, so `-n 3` sends 10.)
3. If both are set and the result count is still capped, the API itself may have been the cap. Check `xr usage --output
   json` to confirm we aren't tier-limited.
4. If still puzzled, the answer is at <https://docs.x.com/x-api/posts/search/introduction.md>; fetch it.

### "The JSON from `xr timeline --output json` has no `status` field. Did it fail?"

1. Check the exit code and the stream: exit `0` with the document on stdout is a success.
2. API-backed verbs print the X API document (`data`, `meta`, `includes`, `errors`); only local verbs (`auth
   …`, `validate`, `skill …`) add `status: "ok"`. [output-envelope.md](output-envelope.md) tabulates the four document
   kinds.
3. Read `.data[]` and `.meta.next_token`; `scripts/paginate.sh` already does, across pages.

Done at step 1; nothing to escalate.

### "A read verb exited 77."

1. Capture the failure itself: `xr whoami --output json 2>&1`. It carries `reason: "auth-required"` and a `next_step`.
2. `xr auth status --output json` → `.apps[]`: is the default app the intended one, and does it list an `oauth2_users`
   entry? (Expiry is not reported; `xr` refreshes silently when a refresh token exists.)
3. Branch on `next_step.action`: `sign-in` / `select-app` / `inspect-store` carry a `command` to run verbatim;
   `register-app` carries a `template` whose placeholders only the user can fill; ask, do not invent.
4. Re-verify with `xr whoami --output json`; expect exit `0` and the `{"data":{…}}` document (no `status` key).

Full recipe: [output-envelope.md § Exit 77 recipe](output-envelope.md#exit-77-recipe).

### "A call answered `reason: "forbidden"`. Is the app broken?"

1. Check for `next_step`. `action: "enroll-app"` means the 403 body named enrollment (`client-not-enrolled` /
   `client-forbidden`): open `next_step.docs`; the fix is in the developer portal.
2. No `next_step`: read `message`, which carries X's problem document. A permission refusal on one endpoint is usually
   a scope the token does not carry (re-run `xr auth oauth2` after the portal grants it) or a tier that does not
   include the endpoint; both are answered by the per-endpoint page on docs.x.com, not by retrying.
3. Neither `forbidden` nor `invalid-request` (400 / 422) is transient. Only `server-error` (5xx) and `network-error`
   (exit `5`, no answer at all) earn one retry.

### "What scope does `xr dm` need?"

1. `xr dm --help` → describes the CLI surface, not the scope.
2. `xr examples` → shows the invocation, not the scope.
3. Companion `x-api` skill → likely has DM scope details under `references/`.
4. Fall through to <https://docs.x.com/x-api/direct-messages/manage/introduction.md>.

Do not guess the scope name. The agent that guesses a plausible-looking scope is the agent that wastes a token refresh
and an hour debugging an `auth-required` envelope; the catalog is a closed set X publishes, and the per-endpoint page
names the scope each call needs.

## When to file a bug

A finding worth filing as `[skill]`-prefixed issue at <https://github.com/brettdavies/xurl-rs/issues/new/choose>:

- This bundle references a flag, command, or output that no longer matches the installed `xr`.
- A template's "before / after" example is wrong.
- A reference doc contradicts the binary's own help.

Not worth a bug:

- "I wish `xr` did X." That's a `xurl-rs` feature request, not a skill issue. Same tracker, different label.
- "This skill is too long." Open a discussion or PR against this bundle directly.
