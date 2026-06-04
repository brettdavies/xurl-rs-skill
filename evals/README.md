# Evals

Self-contained evaluation prompts for the consumer-side behavior of this skill. Each eval dispatches to a fresh agent
session with no prior context, hands it the prompt body, and grades the resulting artifacts against numbered success
criteria.

**Discovery is part of every eval.** No prompt body names the binary, the skill, or the GitHub project. The description
in `SKILL.md`'s frontmatter is the only signal the agent has that this skill applies. If a fresh agent can't find this
skill from the prompt, that's a finding — re-tune the description's trigger keywords.

## Catalog

| Eval                                                                                   | Tests                                                                     | Mutating? |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | --------- |
| [eval-01-discover-and-auth.md](eval-01-discover-and-auth.md)                           | Discovery from a non-binary-named prompt; auth-mode selection             | No        |
| [eval-02-search-and-process.md](eval-02-search-and-process.md)                         | Discovery; `scripts/paginate.sh` selection; cursor-paginated read         | No        |
| [eval-03-compose-dry-run.md](eval-03-compose-dry-run.md)                               | Discovery; `scripts/dry-run-gate.sh` selection; DO-NOT-PUBLISH gate       | Yes       |
| [eval-04-rate-limited-recovery.md](eval-04-rate-limited-recovery.md)                   | Discovery; envelope `reason` lookup; correct first response on rate limit | No        |
| [eval-05-tier-numbers-forced-escalation.md](eval-05-tier-numbers-forced-escalation.md) | Discovery; forced escalation to authoritative external docs               | No        |

## Workdir convention

Each eval creates a fresh workdir at `/tmp/xurl-rs-eval-<N>-$(date +%s)/` and treats it as CWD. Artifacts land there.
Workdir contents are never committed — reproducibility comes from re-running the prompt against a fresh agent.

## Grading

Each eval ships numbered success criteria, each scored independently 0–10. The eval score is the average, rounded to one
decimal. Three categories of artifacts are inspected:

1. **Required files in workdir** (named in the eval's `## Required artifacts` section). Missing one is an automatic 0 on
   that criterion.
2. **`FINAL-REPORT.md` content** — the agent's reflective summary. Required sections vary per eval.
3. **Side effects** — for mutating evals (eval-03), evidence that no live mutation was attempted. See that eval's `##
   Dry-run execution gate` section.

## Running an eval

Dispatch a fresh agent session with the eval prompt body as the user message. No prior context. After the agent
finishes, walk the workdir and the FINAL-REPORT.md to fill in the score sheet.

A graded round produces an `evals/round-<date>.md` summary that classifies each prior eval finding (worked / regressed /
not-touched) and lists new findings worth fixing in the bundle. This file is the input the next round of evals will
regression-test against.

## Iteration loop

Evals are not a one-time gate. The loop is: run → grade → fix bundle issues the eval found → re-run later. Each round's
findings get named explicitly in the next round's "Regression-test prior fixes" section so a fix that silently broke is
caught immediately.

For the convention specification, see `~/.claude/skills/create-agent-skills/references/evals.md`.
