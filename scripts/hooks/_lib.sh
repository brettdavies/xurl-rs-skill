#!/usr/bin/env bash
# Canonical version: 2026.11.03 (generic)
#
# Shared helpers for the git hook pair. Sourced by scripts/hooks/pre-commit and
# scripts/hooks/pre-push, never executed directly.
#
# Seeded to: scripts/hooks/_lib.sh
# Activate the pair per clone: git config core.hooksPath scripts/hooks
#
# Contract every check_* helper honours, so the two hooks stay interchangeable:
#   - takes the file list as positional arguments (the *_all variants take none)
#   - returns 0 on a pass, $HOOK_SKIPPED when it did not run, and the tool's own
#     exit status on a failure. Three outcomes, not two: a skip that returned 0
#     would print a pass line, which is the lie the skip notice exists to
#     prevent.
#   - announces a skip caused by a missing tool on stderr. A silent skip is
#     indistinguishable from a passing check, which is how an under-provisioned
#     machine comes to look green. An empty file list is not announced: nothing
#     staged of a given type is not a gap in the gate.
#   - is driven by `step`, which turns those three outcomes into output and a
#     0/1 status every caller aggregates the same way: `step ... || fail=1`.
#
# Callers cd to the repo root before sourcing, so relative paths resolve.
#
# CUSTOMIZE: this library ships the checks the two templates use. Drop the
# helpers a project has no use for rather than carrying dead code, and add a
# project's own checks here, not inline in one hook, whenever both hooks need
# them.
#
# This repo ships a skill bundle with no cargo workspace, so the Rust helpers
# and the cargo push-scope classifier are gone. Its own checks mirror ci.yml:
# style-severity ShellCheck over CI's paths, markdownlint over every tracked
# doc, the core-env guard at tests/core-env-guard.sh, the fixture tests, and
# the contract harness against the xr release AGENTS.md pins.

# Require bash >= 4.4: mapfile, and safe empty-array expansion under `set -u`.
# Sourced, so return rather than exit, which would kill an interactive shell;
# the sourcing hook aborts on the non-zero return. The hooks re-exec under a
# newer bash before they source this, so this fires only for another caller.
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
  printf 'error: bash >= 4.4 required, but this is bash %s.\n' "${BASH_VERSION:-unknown}" >&2
  printf 'Install a newer bash: brew install bash\n' >&2
  # shellcheck disable=SC2317  # `exit` runs only when executed rather than sourced
  return 1 2>/dev/null || exit 1
fi

# ---------------------------------------------------------------------------
# Output and step dispatch
# ---------------------------------------------------------------------------

# Colour only when stdout is a terminal: a hook run through a pager, a CI log,
# or an agent harness should not carry escape codes.
if [ -t 1 ]; then
  _HOOK_RED=$'\033[0;31m'
  _HOOK_GREEN=$'\033[0;32m'
  _HOOK_BOLD=$'\033[1m'
  _HOOK_RESET=$'\033[0m'
else
  _HOOK_RED=''
  _HOOK_GREEN=''
  _HOOK_BOLD=''
  _HOOK_RESET=''
fi

banner() { printf '%s%s%s\n' "$_HOOK_BOLD" "$1" "$_HOOK_RESET"; }
pass() { printf '  %s✓%s %s\n' "$_HOOK_GREEN" "$_HOOK_RESET" "$1"; }
step_failed() { printf '  %s✗%s %s\n' "$_HOOK_RED" "$_HOOK_RESET" "$1" >&2; }

# The status meaning "this check did not run": distinct from both 0 and a tool
# failure, so `step` can tell a skip from a pass.
HOOK_SKIPPED=99

# Every announced skip goes through here, so no missing tool skips silently.
# Returns HOOK_SKIPPED, so a check guards with `have foo || skip ... || return`.
skip() {
  printf '  - %s (skipped: %s)\n' "$1" "$2" >&2
  return "$HOOK_SKIPPED"
}

have() { command -v "$1" >/dev/null 2>&1; }

# Run one check and report it. `label` names the pass line, `hint` names the
# command to rerun after a failure. Returns 0 on a pass or a skip, 1 on a
# failure.
step() {
  local label="$1" hint="$2" rc
  shift 2
  "$@"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$label"
  elif [ "$rc" -ne "$HOOK_SKIPPED" ]; then
    step_failed "$hint"
    return 1
  fi
}

# Checks that share no resource run together, so the slowest one sets the
# wall-clock instead of the sum. Each buffers its own output and status;
# step_wait replays them in the order they were queued, so the report reads the
# same as a serial run whatever order they finished in.
#
# Never queue two checks that contend for the same lock. Every cargo step takes
# the build lock, so queueing them wins nothing and only hides the contention.
# Anything asserting on wall-clock (a startup-latency budget, a timing test)
# must run alone, before the queue, for the same reason.
_HOOK_BG_DIR=''
_HOOK_BG_LABEL=()
_HOOK_BG_HINT=()

_hook_bg_cleanup() {
  [ -n "$_HOOK_BG_DIR" ] && rm -rf "$_HOOK_BG_DIR"
  _HOOK_BG_DIR=''
  _HOOK_BG_LABEL=()
  _HOOK_BG_HINT=()
  return 0
}

# step_bg <label> <hint> <command>...: queue a check. Same contract as `step`.
step_bg() {
  local label="$1" hint="$2" slot
  shift 2
  if [ -z "$_HOOK_BG_DIR" ]; then
    _HOOK_BG_DIR="$(mktemp -d)"
    # step_wait cleans up on the happy path; the trap covers an early exit.
    trap '_hook_bg_cleanup' EXIT
  fi
  slot="${#_HOOK_BG_LABEL[@]}"
  _HOOK_BG_LABEL+=("$label")
  _HOOK_BG_HINT+=("$hint")
  {
    "$@" >"$_HOOK_BG_DIR/$slot.out" 2>&1
    printf '%s' "$?" >"$_HOOK_BG_DIR/$slot.rc"
  } &
}

# Wait for every queued check and report them in queue order. Returns 1 if any
# failed, 0 when all passed or skipped, matching `step`.
step_wait() {
  local rc=0 i status
  [ -n "$_HOOK_BG_DIR" ] || return 0
  wait
  for i in "${!_HOOK_BG_LABEL[@]}"; do
    status="$(cat "$_HOOK_BG_DIR/$i.rc" 2>/dev/null || true)"
    if [ -s "$_HOOK_BG_DIR/$i.out" ]; then
      cat "$_HOOK_BG_DIR/$i.out" >&2
    fi
    if [ "$status" = "0" ]; then
      pass "${_HOOK_BG_LABEL[$i]}"
    elif [ "$status" != "$HOOK_SKIPPED" ]; then
      step_failed "${_HOOK_BG_HINT[$i]}"
      rc=1
    fi
  done
  _hook_bg_cleanup
  return "$rc"
}

# ---------------------------------------------------------------------------
# Git environment
# ---------------------------------------------------------------------------

# without_git_repo_env <command>...: run a command, or a function from this
# library, in a subshell without git's repository variables.
#
# Git exports GIT_DIR into a hook started from a linked worktree, and
# GIT_INDEX_FILE into pre-commit. A tool that runs git in another directory
# under them (a test that builds a scratch repository, cargo-deny's advisory
# fetch, a build reading --show-toplevel) acts on this repository instead: it
# commits onto the branch, resets it, or resolves the wrong top level.
# Pre-push clears them at its top, because git starts a hook at the worktree
# root and discovery finds the same repository. Pre-commit keeps them and wraps
# such a tool here, because its staged set has to come from the temporary index
# of `commit -a` and `commit <paths>`.
without_git_repo_env() (
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE
  "$@"
)

# ---------------------------------------------------------------------------
# Push scope
# ---------------------------------------------------------------------------

# push_only_deletes: true when every ref line git hands pre-push on stdin,
# `<local ref> <local sha> <remote ref> <remote sha>`, deletes a remote ref.
# A delete carries an all-zero local sha (40 zeros, or 64 in a SHA-256
# repository) and delivers no commit for any check to read.
#
# False, so the checks run, when stdin is a terminal (the hook run by hand),
# when it carries no ref lines, and when it stays open for
# HOOK_STDIN_WAIT_SECONDS (default 5) with no next line. Git writes its lines
# and closes stdin at once, so a real push never waits.
#
# Stdin can be read only once, so every line read is left in HOOK_PUSH_REFS
# for a later step that needs the refs too.
push_only_deletes() {
  local wait_s="${HOOK_STDIN_WAIT_SECONDS:-5}" line local_ref local_sha rc deletes=0 others=0
  HOOK_PUSH_REFS=''
  [ -t 0 ] && return 1
  while :; do
    rc=0
    IFS= read -r -t "$wait_s" line || rc=$?
    # At end of input read returns 1 but still fills line with a last line
    # that has no newline, which counts like any other.
    [ "$rc" -eq 0 ] || { [ "$rc" -le 128 ] && [ -n "$line" ]; } || break
    HOOK_PUSH_REFS+="$line"$'\n'
    read -r local_ref local_sha _ <<<"$line"
    [ -n "$local_ref" ] || continue
    if [[ "$local_sha" =~ ^0+$ ]]; then
      deletes=$((deletes + 1))
    else
      others=$((others + 1))
    fi
  done
  # read returns above 128 on a timeout and 1 at end of input.
  [ "$rc" -le 128 ] && [ "$deletes" -gt 0 ] && [ "$others" -eq 0 ]
}

# push_only_known_commits REMOTE: true when every ref line push_only_deletes
# kept in HOOK_PUSH_REFS deletes or names a commit a REMOTE remote-tracking
# branch already reaches, as a tag or a new branch at a pushed commit does, and
# at least one line names a commit. rev-list peels an annotated tag to its
# commit. False, so the checks run, with no REMOTE (the hook run by hand) and
# with no line that names a commit. A push to a URL instead of a remote name
# matches no remote-tracking branch, so every commit it carries counts as new.
push_only_known_commits() {
  local remote="${1:-}" local_sha known=0
  [ -n "$remote" ] || return 1
  while read -r _ local_sha _; do
    [ -n "${local_sha:-}" ] || continue
    [[ "$local_sha" =~ ^0+$ ]] && continue
    brings_new_commits "$remote" "$local_sha" && return 1
    known=$((known + 1))
  done <<<"${HOOK_PUSH_REFS:-}"
  [ "$known" -gt 0 ]
}

# brings_new_commits REMOTE SHA: true when SHA reaches a commit no REMOTE
# remote-tracking branch reaches, and when git cannot read SHA.
brings_new_commits() {
  local out
  out=$(git rev-list -n 1 "$2" --not --remotes="$1" 2>/dev/null) || return 0
  [ -n "$out" ]
}

# ---------------------------------------------------------------------------
# File selection
# ---------------------------------------------------------------------------

# Staged paths matching the given pathspecs. ACMR only: a deletion cannot fail
# a lint, and the linter would fail trying to open the missing path.
staged() { git diff --cached --name-only --diff-filter=ACMR -- "$@"; }

# Tracked paths matching the given pathspecs that still exist on disk. A file
# deleted from the working tree but not yet committed stays in the index, so
# `git ls-files` still lists it; filtering here is what --diff-filter=ACMR
# already does for the staged set.
tracked() {
  local f
  while IFS= read -r f; do
    [ -e "$f" ] && printf '%s\n' "$f"
  done < <(git ls-files -- "$@")
}

# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------

# Correctness, at style severity: ci.yml's shellcheck job runs style, and the
# whole tracked shell set is clean there.
check_shell() {
  [ "$#" -gt 0 ] || return "$HOOK_SKIPPED"
  have shellcheck || skip "shellcheck" "install via \`brew install shellcheck\`" || return
  shellcheck --severity=style "$@"
}

# Layout. shfmt owns formatting, shellcheck owns correctness. -d reports a diff
# rather than rewriting staged content out from under the commit.
check_shfmt() {
  [ "$#" -gt 0 ] || return "$HOOK_SKIPPED"
  have shfmt || skip "shfmt" "install via \`brew install shfmt\`" || return
  shfmt -i 2 -ci -bn -d "$@"
}

# The shell files with no .sh extension: the hooks themselves, and the stub xr
# the fixture tests run, which ci.yml's shellcheck job lints too.
SHELL_NO_EXT=('scripts/hooks/pre-commit' 'scripts/hooks/pre-push' 'scripts/hooks/_lib.sh' 'fixtures/bin/xr')

# The tracked shell set: *.sh plus SHELL_NO_EXT. The *.sh glob never matches
# *.bats, which shfmt cannot parse, so that exclusion is by file selection
# rather than by flag.
tracked_shell() {
  tracked '*.sh' "${SHELL_NO_EXT[@]}" | sort -u
}

check_shell_all() {
  local files
  mapfile -t files < <(tracked_shell)
  check_shell "${files[@]}"
}

check_shfmt_all() {
  local files
  mapfile -t files < <(tracked_shell)
  check_shfmt "${files[@]}"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# No test resets HOME, USER, TMPDIR, an XDG_* directory, a tool home, or the
# whole value of PATH. The guard ignores paths that are not test files and
# reads its allowlist from beside itself, tests/core-env-allowlist.tsv. The
# sweep also fails on allowlist entries that no longer match a finding. This
# repo keeps the guard under tests/, where ci.yml's scripts-tests job runs it.
check_core_env() {
  [ "$#" -gt 0 ] || return "$HOOK_SKIPPED"
  [ -x tests/core-env-guard.sh ] || skip "core-env guard" "tests/core-env-guard.sh is not in this checkout" || return
  ./tests/core-env-guard.sh "$@"
}

check_core_env_all() {
  [ -x tests/core-env-guard.sh ] || skip "core-env guard" "tests/core-env-guard.sh is not in this checkout" || return
  ./tests/core-env-guard.sh
}

# Print a suite's output only when it fails. Both suites print a PASS line per
# check, which would bury the hook's own report on every clean run.
quiet_unless_failing() {
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || grep -v '^PASS ' <<<"$out"
  return "$rc"
}

# The fixture-driven script tests, as ci.yml's scripts-tests job runs them: the
# stub xr at fixtures/bin/xr replays canned envelopes, with no network.
check_fixture_tests() {
  [ -f tests/run.sh ] || skip "fixture tests" "tests/run.sh is not in this checkout" || return
  quiet_unless_failing bash tests/run.sh
}

# The contract harness against the xr release AGENTS.md pins, as ci.yml's
# contract job runs it. tests/fetch-xr.sh downloads that release once,
# checksum-checked, into a cache outside the repo; without gh, or with no cached
# copy and no network, the step skips and says so.
check_contract() {
  local tag bin
  have gh || skip "contract" "install gh; tests/fetch-xr.sh downloads the pinned xr with it" || return
  tag=$(bash tests/pinned-xr.sh) || return
  bin=$(bash tests/fetch-xr.sh "$tag" 2>/dev/null) || skip "contract" "could not fetch xr $tag (offline?)" || return
  quiet_unless_failing env XR_BIN="$bin" bash tests/contract.sh
}

# ---------------------------------------------------------------------------
# Workflows and markdown
# ---------------------------------------------------------------------------

check_actionlint() {
  [ "$#" -gt 0 ] || return "$HOOK_SKIPPED"
  have actionlint || skip "actionlint" "install via \`brew install actionlint\`" || return
  actionlint "$@"
}

check_actionlint_all() {
  local files
  mapfile -t files < <(tracked '.github/workflows/*.yml' '.github/workflows/*.yaml')
  check_actionlint "${files[@]}"
}

# Concurrency-group namespacing across the workflow set. The file list decides
# whether it runs; the script reads every workflow itself, because the rule is
# a property of the set. Its success line goes to stdout and its findings to
# stderr, so dropping stdout keeps a pass as quiet as every other check.
check_workflow_concurrency() {
  [ "$#" -gt 0 ] || return "$HOOK_SKIPPED"
  [ -x scripts/check-workflow-concurrency.sh ] \
    || skip "concurrency namespacing" "scripts/check-workflow-concurrency.sh is not in this checkout" || return
  ./scripts/check-workflow-concurrency.sh >/dev/null
}

check_workflow_concurrency_all() {
  local files
  mapfile -t files < <(tracked '.github/workflows/*.yml' '.github/workflows/*.yaml')
  check_workflow_concurrency "${files[@]}"
}

# Markdown syntax, judged on the staged content in a scratch tree.
# markdownlint-cli2 rewrites every file it reads when any config on the path
# sets `fix: true` (the canonical config does), with or without --fix, and a
# --config base cannot turn that off because a directory config overrides it.
# So the tree holds each passed file's staged blob and every tracked
# markdownlint config at its own relative path with `fix` flipped off: the
# root ignores and any nested config apply exactly as they do in CI, and
# nothing in the checkout is written. `git show :path` reads the index git
# names in GIT_INDEX_FILE, which is the temporary one during `commit -a` and
# `commit <paths>`.
check_markdown() {
  [ "$#" -gt 0 ] || return "$HOOK_SKIPPED"
  have markdownlint-cli2 || skip "markdownlint" "install via \`brew install markdownlint-cli2\`" || return
  local tree f rc=0
  tree="$(mktemp -d)" || return 1
  while IFS= read -r f; do
    mkdir -p "$tree/$(dirname "$f")"
    git show ":$f" | sed -E 's/^([[:space:]]*"?fix"?[[:space:]]*:[[:space:]]*)true/\1false/' >"$tree/$f"
  done < <(git ls-files -- ':(glob)**/.markdownlint*')
  for f in "$@"; do
    mkdir -p "$tree/$(dirname "$f")"
    git show ":$f" >"$tree/$f" || rc=1
  done
  if [ "$rc" -eq 0 ]; then
    (cd "$tree" && markdownlint-cli2 "$@") || rc=$?
  fi
  rm -rf "$tree"
  return "$rc"
}

# The whole-repo sweep: every tracked doc, which ci.yml's `**/*.md` glob
# reaches, with the config's ignores applied as CI applies them.
check_markdown_all() {
  local files
  mapfile -t files < <(tracked '*.md')
  check_markdown "${files[@]}"
}
