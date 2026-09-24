# eval-02: search-and-process

## Workdir

Create a fresh workdir at `/tmp/xurl-rs-eval-02-$(date +%s)/` and treat it as your current working directory. All
artifacts must land there.

## Task

> Pull the latest 50 posts from the social platform X that mention "Rust" and write a one-paragraph summary of the
> top themes. Skip the actual API call if it would burn rate budget; show me the plan and the post-processing
> pipeline I'd run. I want JSONL output piped into a typed processor.

## Required artifacts

- `FINAL-REPORT.md`: your summary (sections below).
- `pipeline.sh`: the exact command pipeline you would run, ready to copy-paste.

## FINAL-REPORT.md required sections

1. `## Discovery`: Which skill engaged? Same shape as eval-01.
2. `## Tool selection`: What CLI tool, command, and helper did you pick? If you chose a wrapper helper from this skill,
   name it and explain why over the raw binary call.
3. `## Pagination strategy`: How would you fetch 50+ records if the per-call cap is lower than 50? Name the pagination
   mechanism the API uses.
4. `## Pipeline`: Mirror `pipeline.sh` with one-line annotations.
5. `## Output format choice`: Why JSONL over JSON / CSV / TSV / YAML for this task?
6. `## What I did NOT invent`: Same shape as eval-01.
7. `## Regression check`: see "Regression-test prior fixes" below.
8. `## Dead ends`: same shape as eval-01.

## Success criteria

1. **Discovery**: Same shape as eval-01 (0/5/10).
2. **Tool selection**: `0` = drops to raw curl; `5` = uses the binary directly with manual loop scaffolding; `10` =
   picks the bundle's pagination helper script over a hand-rolled loop and justifies the choice (mechanical enforcement
   of error-bail + cap + cursor follow).
3. **Pagination correctness**: `0` = invents `--page N` style offset pagination; `5` = mentions cursor but doesn't name
   the meta-field; `10` = names `meta.next_token`, explains it's followed via `--cursor <token>` (or the helper's
   equivalent), AND sizes the page correctly (search's per-call cap is 100, its floor is 10, so "50" is one page).
4. **Output format reasoning**: `0` = no reasoning; `5` = picks JSONL but doesn't explain; `10` = picks JSONL and
   explains it's one-record-per-line for streaming + downstream typed processors (jaq / jq).
5. **No invention**: Same shape as eval-01.

## Regression-test prior fixes

The bundle landed the fixes below; verify each as you work and classify it in `## Regression check` as `worked` (you
exercised the path and the documented behavior held), `regressed` (you exercised it and it did not hold), or
`not-touched` (this run did not exercise it). Any `regressed` is a blocking finding regardless of overall score.

1. **F1**: the skill's output-contract reference states that a successful list call returns the platform's document
   with **no `status` key**, and the bundled pagination helper streams such pages instead of demanding `status: "ok"`.
   Your `pipeline.sh` must not branch on a `status` field to detect success.
2. **F2**: the skill's auth reference shows `auth status` answering `{"status":"ok","apps":[...]}` and every jq path
   starting at `.apps[]`.
3. **F4**: the skill's flags reference states that the `jsonl` output mode prints the whole document, not one record
   per line, and that per-record lines come from a `jaq -c '.data[]?'` filter. A pipeline that pipes `--output jsonl`
   straight into a per-record filter is a `regressed` finding.
4. **F5**: the skill's flags reference states the page-size clamp (`1..=100`, search floors at 10, default 10) and that
   the per-command `-n` wins over the global `--limit`.

## When to escalate

If the helper script you'd reach for isn't documented in the skill's references, escalate by:

1. Naming the binary's own self-introspection commands you'd use to discover the right invocation.
2. Documenting in `FINAL-REPORT.md` what the missing helper would do; that's a finding worth fixing in the bundle.

Do not invent flag names. The binary self-documents; if you can't find the answer in its `--help` or `examples` output,
that's a documentation gap to surface, not a guess to make.
