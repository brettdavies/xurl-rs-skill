# eval-01 — discover-and-auth

## Workdir

Create a fresh workdir at `/tmp/xurl-rs-eval-01-$(date +%s)/` and treat it as your current working directory for this
eval. All artifacts must land there. Do not contaminate the user's home directory or repo.

## Task

> I want to start using the social platform X from the command line for the first time. I've heard the auth flow is
> a bit involved — there's something about OAuth scopes and multiple modes for desktop vs server. I'm on a Linux
> desktop with a browser. Help me get set up end-to-end. Don't actually run anything that hits the live API; I just
> want a plan I can execute and verify.

## Required artifacts

Before you finish, the workdir must contain:

- `FINAL-REPORT.md` — your summary (sections below).
- `plan.sh` — the exact commands a user would run, in order, to complete the setup.

## FINAL-REPORT.md required sections

1. `## Discovery` — Which skill (if any) covered this task? Did you discover it from the user phrasing alone, or did you
   need to look elsewhere? If you didn't find a skill, what would you have wanted the skill description to say?
2. `## Auth mode chosen` — Which auth path did you recommend and why? Name the OAuth flow precisely and explain why it
   fits the user's stated environment (Linux desktop with browser).
3. `## Plan` — Mirror the contents of `plan.sh` here, with one-line annotations explaining each step.
4. `## Verification step` — How does the user confirm the setup worked? Name the exact verification command.
5. `## What I did NOT invent` — Specifically list anything you DID NOT name from memory: OAuth scope identifiers,
   tier-specific endpoint URLs, billing tiers, rate-limit numbers. If you didn't need to invent any, say so.
6. `## Dead ends` — Anything you tried that didn't pan out; what blocked you; what you'd do next. Acceptable; an
   undocumented dead end caps the eval score at 5.

## Success criteria

Each criterion is independently scored 0-10. The eval score is the average, rounded to one decimal.

1. **Discovery** — Did the agent discover the right skill from the prompt body alone (no naming the binary in the
   prompt)? `0` = no skill engaged; `5` = found via secondary search; `10` = matched on description triggers directly.
2. **Auth-mode correctness** — Was the chosen auth path appropriate for the user's environment? `0` = wrong mode (e.g.,
   suggested app-only Bearer when user needs to POST); `5` = correct mode but no justification; `10` = correct mode with
   reasoning that mentions the TTY-vs-headless distinction.
3. **Plan completeness** — Does `plan.sh` cover everything from "no auth configured" to "verified working"? `0` =
   missing steps; `5` = covers the happy path but no verification; `10` = covers app registration (if needed), flow
   execution, and the verification call.
4. **No invention** — Did the agent invent OAuth scope names, billing tiers, rate-limit numbers, or specific endpoint
   paths from memory? `0` = invented a specific scope name not present in the skill; `5` = vague gestures at "the
   appropriate scope"; `10` = explicitly defers to the developer-portal app config + the authoritative docs URL for
   scope details.
5. **Hygiene** — Are secrets handled correctly? `0` = `--client-secret "actual-value"` inline anywhere in `plan.sh`; `5`
   = secrets are env-var-referenced but no source named; `10` = secrets are pulled from a secrets manager (op /
   1Password CLI / similar) with an explicit reference like `$(op read op://...)` or `$XURL_BEARER_TOKEN`.

## Regression-test prior fixes

This is eval-01. No prior eval findings exist; nothing to regression-test. In `FINAL-REPORT.md` add a one-line `##
Regression check` section that states: "This is the inaugural eval round; no prior findings to verify."

## When to escalate

If you cannot find a skill that matches this task from its description, escalate by:

1. Documenting in `FINAL-REPORT.md § Discovery` that no skill was discovered.
2. Falling back to the user's first principles: tell them what you'd Google for if you had to start from scratch.
3. Naming the agent-friendly URL pattern at `docs.x.com/<page>.md` as the primary external source.

Do not invent flag names, scope names, or endpoint paths. If the skill isn't loaded and you don't have authoritative
docs in front of you, the right answer is "I don't know the specifics; here are the categories of question you'd ask the
docs."
