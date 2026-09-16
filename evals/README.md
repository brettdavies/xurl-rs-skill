# Evals

Self-contained evaluation prompts for the consumer-side behavior of this skill. Each eval dispatches to a fresh agent
session with no prior context, hands it the prompt body, and grades the resulting artifacts against numbered success
criteria.

**Discovery is part of every eval.** No prompt body names the binary, the skill, or the GitHub project. The description
in `SKILL.md`'s frontmatter is the only signal the agent has that this skill applies. If a fresh agent can't find this
skill from the prompt, that's a finding; re-tune the description's trigger keywords.

## Catalog

| Eval                                                                                   | Tests                                                                                  | Mutating? | Regression-tests | Re-run when                                                                      |
| -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | --------- | ---------------- | -------------------------------------------------------------------------------- |
| [eval-01-discover-and-auth.md](eval-01-discover-and-auth.md)                           | Discovery from a non-binary-named prompt; auth-mode selection                          | No        | none (inaugural) | `SKILL.md` description, `auth-modes.md`, `oauth2-setup.md` change                |
| [eval-02-search-and-process.md](eval-02-search-and-process.md)                         | Discovery; `scripts/paginate.sh` selection; cursor-paginated read                      | No        | F1 F2 F4 F5      | `paginate.sh`, `agent-flags.md`, `search-and-process.md` change                  |
| [eval-03-compose-dry-run.md](eval-03-compose-dry-run.md)                               | Discovery; `scripts/dry-run-gate.sh` selection; DO-NOT-PUBLISH gate                    | Yes       | F1 F3 F6 F7      | `dry-run-gate.sh`, `output-envelope.md`, `post-reply-thread.md` change           |
| [eval-04-rate-limited-recovery.md](eval-04-rate-limited-recovery.md)                   | Discovery; envelope `reason` lookup; correct first response on rate limit              | No        | F1 F2 F3         | `output-envelope.md` reason catalog or `next_step` change                        |
| [eval-05-tier-numbers-forced-escalation.md](eval-05-tier-numbers-forced-escalation.md) | Discovery; forced escalation to authoritative external docs                            | No        | F2 F3            | `escalation.md`, `x-api-essentials.md` change                                    |
| [eval-06-moderate-mentions.md](eval-06-moderate-mentions.md)                           | Discovery; `muted` list via `paginate.sh`; `block` via the gate; no `--force` on block | Yes       | F1 F4 F5 F6 F8   | any change to the social-graph surface, either script, or the envelope reference |

## Fixes under regression test

Every eval from eval-02 on carries a "Regression-test prior fixes" section that names entries from this list by id. The
agent classifies each named entry as `worked` / `regressed` / `not-touched` in `FINAL-REPORT.md`; any `regressed` is a
blocking finding. Add an entry here when a bundle fix lands that a future eval could silently undo; retire one when the
surface it guards is gone.

| Id | Where                                                                           | Expected behavior                                                                                                                                                                                      |
| -- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| F1 | `references/output-envelope.md` § "The four kinds"; `scripts/paginate.sh`       | An API-backed success is the raw document with **no `status` key**; the paginator streams such pages and never demands `status: "ok"`                                                                  |
| F2 | `references/auth-modes.md` § "What `auth status` returns"                       | `auth status` / `auth apps list` answer `{"status":"ok","apps":[...]}`; every jq path starts at `.apps[]`; no `expires_at` field                                                                       |
| F3 | `references/output-envelope.md` § "`next_step`" and § "Exit 77 recipe"          | `next_step.action` is the closed set `register-app` / `sign-in` / `select-app` / `inspect-store` / `enroll-app`; `command` is verbatim-safe, `template` needs user values; `rate-limited` carries none |
| F4 | `references/agent-flags.md` § "Output format"                                   | `--output jsonl` prints the whole document, not one record per line; per-record lines come from `jaq -c '.data[]?'`                                                                                    |
| F5 | `references/agent-flags.md` § "`--limit` and `-n/--max-results`"                | Page size clamps to `1..=100`; `search` floors at 10; default 10; `-n` wins over `--limit`                                                                                                             |
| F6 | `scripts/dry-run-gate.sh`; `templates/post-reply-thread.md` § "Delete"          | The gate refuses a `delete` preflight without `--force` and says to pass `--force`; `block` / `mute` / `follow` need no `--force`                                                                      |
| F7 | `references/self-introspection.md` § 3 and § 4                                  | `xr schema <name>` is positional; `validate --schema` knows `block`; `--schema envelope` rejects an API-backed success                                                                                 |
| F8 | `templates/media-upload.md` § "Upload, synchronous" and § "Pre-flight"          | The media id is `.data.id`; `--dry-run` does not stat the file; a bearer-only app answers `auth-method-mismatch`                                                                                       |

## Workdir convention

Each eval creates a fresh workdir at `/tmp/xurl-rs-eval-<N>-$(date +%s)/` and treats it as CWD. Artifacts land there.
Workdir contents are never committed; reproducibility comes from re-running the prompt against a fresh agent.

## Grading

Each eval ships numbered success criteria, each scored independently 0–10. The eval score is the average, rounded to one
decimal. Three categories of artifacts are inspected:

1. **Required files in workdir** (named in the eval's `## Required artifacts` section). Missing one is an automatic 0 on
   that criterion.
2. **`FINAL-REPORT.md` content**: the agent's reflective summary. Required sections vary per eval.
3. **Side effects**: for mutating evals (eval-03, eval-06), evidence that no live mutation was attempted. See each
   eval's `## Dry-run execution gate` section.

## Running an eval

Dispatch a fresh agent session with the eval prompt body as the user message. No prior context. After the agent
finishes, walk the workdir and the FINAL-REPORT.md to fill in the score sheet.

A graded round produces an `evals/round-<date>.md` summary that classifies each fix id above (worked / regressed /
not-touched) and lists new findings worth fixing in the bundle. This file is the input the next round of evals will
regression-test against.

## Iteration loop

Evals are not a one-time gate. The loop is: run → grade → fix bundle issues the eval found → re-run later. Each round's
findings get an id in the table above so a fix that silently broke is caught immediately.

The convention these prompts follow (eight properties of a good eval prompt, the dry-run gate, the leak-grep defense) is
the `evals.md` reference of the `create-agent-skills` skill in the `brettdavies/agent-skills` repository.
