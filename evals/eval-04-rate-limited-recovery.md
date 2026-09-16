# eval-04: rate-limited recovery

## Workdir

Create a fresh workdir at `/tmp/xurl-rs-eval-04-$(date +%s)/` and treat it as CWD. All artifacts must land there.

## Task

> I just ran a CLI tool against the social platform X and it printed this on stderr then exited:
>
> ```json
> {"status":"error","reason":"rate-limited","exit_code":3}
> ```
>
> What does this mean and what should I do? Specifically: how do I figure out whether I should wait it out, switch
> to a different auth path, or pivot to a cached source?

## Required artifacts

- `FINAL-REPORT.md`: your summary (sections below).
- `next-steps.sh`: exact commands the user should run to triage and recover.

## FINAL-REPORT.md required sections

1. `## Discovery`: Same shape as eval-01.
2. `## Envelope interpretation`: What does each field of the error JSON mean? Don't paraphrase from memory; cite the
   reference doc in the skill that defines them.
3. `## Triage commands`: Mirror `next-steps.sh` with annotations explaining what each command tells the user.
4. `## Decision tree`: Given the output of the triage commands, what's the right next move? Wait? Pivot? Swap auth
   modes? Be specific about the conditions for each branch.
5. `## What I did NOT invent`: Same shape as eval-01. Specifically: did you invent a specific rate-limit number (e.g.,
   "you're limited to 100 calls per 15 minutes")? You should NOT have.
6. `## Regression check`: Classify each named eval-01/02/03 finding as `worked` / `regressed` / `not-touched`. Any
   `regressed` is blocking.
7. `## Dead ends`: Same shape as eval-01.

## Success criteria

1. **Discovery**: Same shape as eval-01 (0/5/10).
2. **Envelope decode correctness**: `0` = misnamed a field; `5` = decoded `reason` correctly but didn't tie it to the
   exit-code mapping; `10` = decoded all three fields against the bundle's documented schema (closed-set reason catalog
   - exit-code mapping table) AND noted that no `next_step` is present: the binary attaches one only when a credential
   or enrollment fix exists, and a rate limit has neither.
3. **Triage commands correctness**: `0` = no triage; `5` = says "check rate limits" without naming the command; `10` =
   names the binary's `usage` subcommand (and its `credits` form for pay-per-use projects) with `--output json` for
   machine reading AND a command that reads the current auth state so the user knows which token bucket is exhausted,
   reading its entries as the bare top-level array it is (`.[]`) rather than expecting a wrapper object.
4. **Decision-tree quality**: `0` = "just wait" with no condition; `5` = wait/pivot but vague conditions; `10` =
   conditional tree keyed on usage output AND the entries of auth status (`bearer` vs `oauth2_users` decides
   which bucket the call drew from), with explicit "if X, then Y" rules.
5. **No rate-limit-number invention**: `0` = quoted a specific number from memory; `5` = hedged with "around X"; `10` =
   explicitly deferred specifics to the platform's docs and the binary's `usage` output. The skill's x-api-essentials
   reference is intentionally drift-resistant on this exact point.

## Regression-test prior fixes

The bundle landed the fixes below; verify each as you work and classify it in `## Regression check` as `worked` /
`regressed` / `not-touched`. Any `regressed` is a blocking finding regardless of overall score.

1. **F1**: the skill's output-contract reference decides the document kind by exit code and stream first (`3` on
   stderr here), and states that a success would have been the platform's document with no `status` key.
2. **F2**: the auth-state command in your `next-steps.sh` reads `.[]` from the bare top-level array and does not look
   for an `expires_at` field.
3. **F3**: the reason catalog says `rate-limited` carries no `next_step`, and your envelope interpretation says so
   rather than treating its absence as a parse problem.

## When to escalate

If the skill doesn't document the envelope's `reason` catalog or doesn't expose a usage-introspection command, escalate
by:

1. Naming the platform's docs URL pattern as the authoritative source on rate-limit windows and budgets.
2. Documenting the gap in `FINAL-REPORT.md` as a finding worth fixing.

Do not invent rate-limit numbers. The bundle's x-api-essentials reference is deliberately drift-resistant; an agent that
quotes a specific cap from memory is using a stale source, not a current one.
