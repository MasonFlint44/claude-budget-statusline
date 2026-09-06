#!/usr/bin/env bash
# Headless skill checks: run each case's prompt through `claude -p` with this
# plugin loaded, against a throwaway config dir, then check the files it
# left behind. Every run is a paid model call, so this is run by hand, not
# in CI.
#
#   tests/skills/run.sh [-m MODEL] [-n RUNS] [CASE...]
#     -m MODEL  model alias or id (default: sonnet)
#     -n RUNS   runs per case (default: 1)
#     CASE      case names under tests/skills/cases/ (default: all)
#
# A case is a directory with:
#   prompt     the user's message (a natural-language ask, or /skill args)
#   setup.sh   sourced before the run with $CFG (the throwaway config dir,
#              already holding a copy of the credentials), $REPO, $WORK
#   check.sh   sourced after the run with the same, plus $OUT (the result
#              text) and $RESULT (the result JSON); a non-zero `fail` count
#              fails the case. Helpers: expect, expect_file, expect_no_warnings.
#
# The throwaway config dir gets a copy of ~/.claude/.credentials.json (or
# $CLAUDE_CONFIG_DIR's); if the CLI refreshes the token during a run the copy
# is copied back so the real file never goes stale. Set ANTHROPIC_API_KEY to
# avoid touching the credentials at all. Results and transcripts land in
# tests/skills/results/<timestamp>/.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
MODEL=sonnet; RUNS=1
while getopts m:n: o; do case $o in m) MODEL=$OPTARG ;; n) RUNS=$OPTARG ;; *) exit 2 ;; esac; done; shift $((OPTIND - 1))
CASES=("$@"); [ ${#CASES[@]} -gt 0 ] || mapfile -t CASES < <(cd "$HERE/cases" && find . -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
REAL_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP=$(date +%Y%m%d-%H%M%S); RES="$HERE/results/$STAMP"; mkdir -p "$RES"
TOOLS="Skill,Bash,Read,Edit,Write,Glob,Grep,MultiEdit"
# Permissions are bypassed for the run: Claude Code always asks before a
# write to settings.json (an allow rule does not cover it), and a headless
# run cannot answer, so the install cases could never wire statusLine under
# dontAsk. Test-only: the shipped plugin and the installer run under the
# user's normal permission prompts. The run still works inside a throwaway
# config dir and cwd; the model can reach the rest of the machine through
# Bash either way, as it could under dontAsk with Bash allowed.

# --- check helpers (available to check.sh) ---
fail=0
expect() { [ "$1" = "$2" ] || { echo "    expected: $2"; echo "    got:      $1"; fail=$((fail + 1)); }; }   # expect ACTUAL EXPECTED
expect_file() {  # expect_file FILE REGEX [MESSAGE]: a line matching REGEX exists in FILE
    grep -Eq -- "$2" "$1" 2>/dev/null || { echo "    ${3:-no line matching /$2/ in ${1#"$CFG"/}}"; fail=$((fail + 1)); }
}
expect_no_file_match() { grep -Eq -- "$2" "$1" 2>/dev/null && { echo "    ${3:-unexpected /$2/ in ${1#"$CFG"/}}"; fail=$((fail + 1)); }; return 0; }
expect_out() { case "$OUT" in *"$1"*) ;; *) echo "    output lacks: $1"; fail=$((fail + 1)) ;; esac; }
expect_no_warnings() {  # the installed calendar parses clean
    local err; err=$(bash "$CFG/statusline/budget-statusline.sh" --calendar 2>&1 >/dev/null)
    [ -z "$err" ] || { echo "    calendar warnings:"; printf '%s\n' "$err" | sed 's/^/      /'; fail=$((fail + 1)); }
}
# scaffold_installed: the plugin already installed under $CFG, settings wired,
# optionally with inline knobs before the script path ($1).
scaffold_installed() {
    mkdir -p "$CFG/statusline/config"
    cp "$REPO/statusline/budget-statusline.sh" "$CFG/statusline/"
    cp "$REPO/statusline/config/calendar.conf" "$CFG/statusline/config/"
    printf '{"statusLine":{"type":"command","command":"%sbash %s/statusline/budget-statusline.sh"}}\n' "${1:-}" "$CFG" > "$CFG/settings.json"
}

total=0; passed=0; cost_all=0
for case in "${CASES[@]}"; do
    CDIR="$HERE/cases/$case"; [ -r "$CDIR/prompt" ] || { echo "no such case: $case"; continue; }
    for ((run = 1; run <= RUNS; run++)); do
        total=$((total + 1))
        WORK=$(mktemp -d); CFG="$WORK/claude"; mkdir -p "$CFG" "$WORK/cwd" "$WORK/home"
        printf '{"hasCompletedOnboarding":true}\n' > "$CFG/.claude.json"
        [ -n "${ANTHROPIC_API_KEY:-}" ] || cp "$REAL_CFG/.credentials.json" "$CFG/.credentials.json"
        fail=0
        # shellcheck disable=SC1090,SC1091
        . "$CDIR/setup.sh"
        RESULT="$RES/$case-$run.json"
        # HOME is throwaway too, so a run that reasons in terms of ~/.claude
        # lands in the sandbox rather than in the real config (permissions are
        # bypassed for the run; see below).
        ( cd "$WORK/cwd" && HOME="$WORK/home" CLAUDE_CONFIG_DIR="$CFG" claude -p "$(cat "$CDIR/prompt")" --plugin-dir "$REPO" --model "$MODEL" \
              --output-format json --permission-mode bypassPermissions --allowedTools "$TOOLS" --max-turns 40 --max-budget-usd 2 \
              --setting-sources user < /dev/null ) > "$RESULT" 2> "$RES/$case-$run.stderr"
        rc=$?
        # A refreshed token goes back where the CLI expects it next time.
        if [ -z "${ANTHROPIC_API_KEY:-}" ] && ! cmp -s "$CFG/.credentials.json" "$REAL_CFG/.credentials.json"; then
            cp "$CFG/.credentials.json" "$REAL_CFG/.credentials.json" && echo "  (credentials refreshed during the run; copied back)"
        fi
        OUT=$(jq -r '.result // ""' "$RESULT" 2>/dev/null); cost=$(jq -r '(.total_cost_usd // 0) * 1000 | round / 1000' "$RESULT" 2>/dev/null)
        turns=$(jq -r '.num_turns // "?"' "$RESULT" 2>/dev/null)
        [ "$rc" = 0 ] || { echo "    claude exited $rc: $(head -c 300 "$RES/$case-$run.stderr")"; fail=$((fail + 1)); }
        # shellcheck disable=SC1090,SC1091
        . "$CDIR/check.sh"
        printf '%s\n' "$OUT" > "$RES/$case-$run.out"
        if [ "$fail" = 0 ]; then passed=$((passed + 1)); verdict=PASS; else verdict=FAIL; fi
        printf '%-4s %-28s run %s  %s turns  $%s\n' "$verdict" "$case" "$run" "$turns" "$cost"
        cost_all=$(awk -v a="$cost_all" -v b="${cost:-0}" 'BEGIN{printf "%.4f", a + b}')
        # The session transcript, for reading how the run went wrong.
        find "$CFG/projects" -name '*.jsonl' -exec cp {} "$RES/$case-$run.transcript.jsonl" \; 2>/dev/null
        rm -rf "$WORK"
    done
done
printf '\n%s/%s passed, model %s, $%s total; transcripts in %s\n' "$passed" "$total" "$MODEL" "$cost_all" "${RES#"$REPO"/}"
[ "$passed" = "$total" ]
