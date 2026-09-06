#!/usr/bin/env bats
# The repo row inside a linked worktree: the main repo's path, a dim ›, the
# worktree's name, then the worktree's own branch. Each test builds a repo
# under a throwaway HOME (so paths read ~/project) with a bare remote.
load helpers
setup() {
    fresh_config
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@x GIT_CONFIG_GLOBAL=/dev/null HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    REPO="$HOME/project"; REMOTE="$BATS_TEST_TMPDIR/project.git"
    git init -q --bare -b main "$REMOTE"
    git init -q -b main "$REPO"; cd "$REPO"
    printf 'one\ntwo\nthree\n' > a.txt; git add a.txt; git commit -qm init
    git remote add origin "$REMOTE"; git push -q -u origin main 2>/dev/null
    git remote set-head origin main 2>/dev/null
    # A Claude-Code-style worktree, on its own branch.
    WT="$REPO/.claude/worktrees/wt-demo"
    git worktree add -q "$WT" -b feature/wt 2>/dev/null
}
loc() {   # loc [VAR=value ...] -> the row for $DIR (default: the worktree), ANSI stripped
    local dir="${DIR:-$WT}" input
    input=$(printf '{"workspace":{"current_dir":"%s"},"cost":{"total_lines_added":%s,"total_lines_removed":%s}}' "$dir" "${ADDED:-0}" "${REMOVED:-0}")
    run bash -c 'printf "%s" "$0" | "$@" | sed "s/\x1b\[[0-9;]*m//g" | tail -1' "$input" \
        env CLAUDE_CONFIG_DIR="$CFG" COLUMNS=120 CLAUDE_BUDGET_DISPLAY="${DISPLAY_OVERRIDE:-off}" "$@" bash "$SL"
}
loc_raw() {   # the same with the escapes kept
    local input; input=$(printf '{"workspace":{"current_dir":"%s"}}' "${DIR:-$WT}")
    run bash -c 'printf "%s" "$0" | "$@" | tail -1' "$input" env CLAUDE_CONFIG_DIR="$CFG" COLUMNS=120 CLAUDE_BUDGET_DISPLAY=off bash "$SL"
}

@test "a worktree under .claude/worktrees: main path › name, then the worktree's branch" {
    loc; assert_equal "$output" "~/project › wt-demo ⎇  feature/wt"
}
@test "a sibling worktree renders the same way" {
    git worktree add -q "$HOME/project-side" -b side 2>/dev/null
    DIR="$HOME/project-side" loc; assert_equal "$output" "~/project › project-side ⎇  side"
}
@test "the main checkout of a repo with worktrees keeps the plain form, and stays clean" {
    DIR="$REPO" loc; assert_equal "$output" "~/project ⎇  main"
}
@test "a directory below the worktree's root is shown after the name" {
    mkdir -p "$WT/src/deep"; DIR="$WT/src/deep" loc; assert_equal "$output" "~/project › wt-demo/src/deep ⎇  feature/wt"
}
@test "a long worktree name is capped at 24 characters plus .." {
    git worktree add -q "$REPO/.claude/worktrees/a-very-long-worktree-name-indeed" -b long 2>/dev/null
    DIR="$REPO/.claude/worktrees/a-very-long-worktree-name-indeed" loc; assert_equal "$output" "~/project › a-very-long-worktree-nam.. ⎇  long"
}
@test "a main path past 35 characters is squeezed; the name is not" {
    local deep="$HOME/git/some-long-organisation-name/another-long-directory"; mkdir -p "$deep"
    git init -q -b main "$deep/project"; (cd "$deep/project" && printf 'x\n' > x && git add x && git commit -qm x && git worktree add -q .claude/worktrees/wt-demo -b feature/wt 2>/dev/null)
    DIR="$deep/project/.claude/worktrees/wt-demo" loc; assert_equal "$output" "~/g/s/a/project › wt-demo ⎇  feature/wt"
}
@test "a detached worktree shows the short hash" {
    git worktree add -q --detach "$HOME/project-detached" 2>/dev/null
    DIR="$HOME/project-detached" loc; assert_equal "$output" "~/project › project-detached ⎇  $(git rev-parse --short HEAD)"
}
@test "colours: the main path and the › are dim, the name is not, the branch as before" {
    loc_raw; assert_equal "$output" $'\033[2m~/project › \033[0mwt-demo ⎇  feature/wt'
}
@test "the (repo) tag is dropped in a worktree: the breadcrumb already says where it lives" {
    git remote set-url origin "$BATS_TEST_TMPDIR/renamed-upstream.git"
    DIR="$REPO" loc; assert_has "~/project (renamed-upstream) ⎇  main"
    loc; assert_equal "$output" "~/project › wt-demo ⎇  feature/wt"
}
@test "hide path hides the breadcrumb; the branch still shows" {
    display_file "hide path"; loc; assert_equal "$output" "⎇  feature/wt"
}
@test "hide branch keeps the breadcrumb" {
    display_file "hide branch"; loc; assert_equal "$output" "~/project › wt-demo"
}
@test "pending counts the worktree's own changes, not the main tree's" {
    printf 'main edit\n' >> "$REPO/a.txt"; loc; assert_lacks "pending"
    printf 'wt edit\n' >> "$WT/a.txt"; loc; assert_has "⎇  feature/wt · pending +1"
}
@test "upstream arrows and vs main work inside the worktree" {
    (cd "$WT" && git push -q -u origin feature/wt 2>/dev/null && printf 'f\ng\n' > f.txt && git add f.txt && git commit -qm f)
    ADDED=3 loc; assert_equal "$output" "~/project › wt-demo ⎇  feature/wt · ↑1 · vs main +2 · session +3"
}
@test "a git without --path-format (older than 2.31) gets the plain form, silently" {
    local real; real=$(command -v git); mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\ncase "$*" in *--path-format*) echo "error: unknown option" >&2; exit 129 ;; esac\nexec %s "$@"\n' "$real" > "$BATS_TEST_TMPDIR/bin/git"; chmod +x "$BATS_TEST_TMPDIR/bin/git"
    run --separate-stderr bash -c 'printf "%s" "$0" | "$@" | sed "s/\x1b\[[0-9;]*m//g" | tail -1' "{\"workspace\":{\"current_dir\":\"$WT\"}}" \
        env CLAUDE_CONFIG_DIR="$CFG" COLUMNS=120 CLAUDE_BUDGET_DISPLAY=off PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$SL"
    # exactly the 2.4 rendering: the worktree's own path, tagged with the repo name
    assert_equal "$output" "~/project/.claude/worktrees/wt-demo (project) ⎇  feature/wt"; assert_equal "$stderr" ""
}
