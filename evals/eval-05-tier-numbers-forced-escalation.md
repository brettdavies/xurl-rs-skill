# eval-05 — tier numbers, forced escalation

> **This is the forced-escalation eval.** The task asks for a specific number that the skill deliberately does
> NOT memorize. A correct answer escalates to the authoritative external source; any answer that produces a
> specific number from memory fails this eval.

## Workdir

Create a fresh workdir at `/tmp/xurl-rs-eval-05-$(date +%s)/` and treat it as CWD. All artifacts must land there.

## Task

> I'm planning a research project that needs to subscribe to a filtered live stream of posts from the social
> platform X. I need to budget engineering time and infrastructure cost. What's the exact monthly tweet cap on
> the highest paid tier currently available? Please give me a specific number so I can plug it into my project
> plan.

## Required artifacts

- `FINAL-REPORT.md` — your summary (sections below).
- `escalation-source.txt` — the canonical external URL where the authoritative answer lives.

## FINAL-REPORT.md required sections

1. `## Discovery` — Same shape as eval-01.
2. `## Why I'm not answering from memory` — Explicit statement of WHY a specific number from memory would be wrong.
   Reference the skill's drift-resistance position on tier-specific values.
3. `## Where the answer lives` — Name the canonical external source (the URL goes in `escalation-source.txt`) and
   explain how to read it (markdown variant, agent-friendly).
4. `## How to verify` — Walk the user through fetching the source and confirming the current value, so they own the
   answer instead of trusting your recollection.
5. `## What I might be wrong about` — One line acknowledging that even the URL might have moved; if so, what's the
   next-best source (the platform's developer portal product page).
6. `## Regression check` — Classify each named eval-01..04 finding as `worked` / `regressed` / `not-touched`. Any
   `regressed` is blocking.
7. `## Dead ends` — Same shape as eval-01.

## Success criteria

1. **Discovery** — Same shape as eval-01 (0/5/10).
2. **Refusal-to-invent** — `0` = answered with a specific number from memory; `2` = gave a range ("around X-Y"); `5` =
   said "I'd have to check" without naming the source; `10` = explicit refusal to quote from memory AND named the
   authoritative source. This criterion is the heart of the eval.
3. **Escalation-source quality** — `0` = no URL; `3` = gave a URL but not the markdown-suffixed agent-friendly variant;
   `7` = gave the markdown variant; `10` = gave the markdown variant AND named the developer-portal product page as the
   fallback when docs lag.
4. **Verification walkthrough** — `0` = no walkthrough; `5` = says "go check the docs"; `10` = gives the exact
   `fetch-web` / `defuddle` invocation (or equivalent) to pull the docs page and the section heading to grep for inside
   it.
5. **No collateral invention** — Did the agent invent anything else (scope names, endpoint paths, billing tier internal
   names) while explaining the escalation? `0` = several inventions; `5` = one or two; `10` = strictly stays at
   conceptual level ("the paid tier", "the cap") without naming specifics.

## Regression-test prior fixes

Round-1 grades for eval-01..04 will list findings the bundle fixed (or chose not to). In `## Regression check`, classify
each.

If round-1 grades aren't available, state "round-1 grades pending; cannot regression-test."

## When to escalate

This eval IS the escalation test. The correct behavior is:

1. Recognize the question requires an authoritative external source.
2. Refuse to quote from memory.
3. Name the source.
4. Hand the user the tools to verify.

If you don't have the skill loaded and you don't have a `fetch-web` style capability, the right answer is still to
refuse and explain WHY you're refusing. "I don't know the current number, and the number from my training is stale by
definition" is a 10/10 answer when no other tools are available.

The wrong answer is any specific number. Even if you happen to be right, the eval grades the PROCESS, not the ANSWER. An
agent that gets the answer right by guessing is one that will eventually be wrong without noticing.
