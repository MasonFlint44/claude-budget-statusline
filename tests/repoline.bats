#!/usr/bin/env bats
# The location row: path, branch, pending churn, upstream arrows, the
# comparison against the default branch, and session churn. Each test builds
# a throwaway repository (with a bare clone as its remote) in the test's tmpdir.
load helpers
setup() {
    fresh_config
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@x GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@x GIT_CONFIG_GLOBAL=/dev/null HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    REPO="$BATS_TEST_TMPDIR/project"
    REMOTE="$BATS_TEST_TMPDIR/project.git"   # same name as the checkout, so no (repo) suffix
    git init -q --bare -b main "$REMOTE"
    git init -q -b main "$REPO"; cd "$REPO"
    printf 'one\ntwo\nthree\n' > a.txt; git add a.txt; git commit -qm init
    git remote add origin "$REMOTE"; git push -q -u origin main 2>/dev/null
    git remote set-head origin main 2>/dev/null
}
# loc [VAR=value ...] -> $output = the location row only, for $REPO (or $DIR).
# No display file unless display_file wrote one, so every group shows.
loc() {
    local dir="${DIR:-$REPO}" input
    input=$(printf '{"workspace":{"current_dir":"%s"},"cost":{"total_lines_added":%s,"total_lines_removed":%s}}' "$dir" "${ADDED:-0}" "${REMOVED:-0}")
    run bash -c 'printf "%s" "$0" | "$@" | sed "s/\x1b\[[0-9;]*m//g" | tail -1' "$input" \
        env CLAUDE_CONFIG_DIR="$CFG" COLUMNS=120 CLAUDE_SPEND_DISPLAY="${DISPLAY_OVERRIDE:-off}" "$@" bash "$SL"
}

@test "clean repo on main: just the path and branch" {
    loc; [[ "$output" == *"/project ⎇  main" ]] || { echo "got: $output"; false; }; assert_lacks "(" "pending" "·"
}
@test "the path is tilde-shortened under HOME" {
    mv "$REPO" "$HOME/project"; DIR="$HOME/project" loc; assert_equal "$output" "~/project ⎇  main"
}
@test "a deep path past 35 characters squeezes the middle components" {
    local deep="$HOME/git/some-long-organisation-name/another-long-directory/project"
    mkdir -p "$(dirname "$deep")"; mv "$REPO" "$deep"; DIR="$deep" loc
    assert_equal "$output" "~/g/s/a/project ⎇  main"
}
@test "a directory that is not a repo: path only" {
    DIR="$BATS_TEST_TMPDIR" loc; assert_equal "$output" "$BATS_TEST_TMPDIR"
}
@test "uncommitted edits: pending +A/-R" {
    printf 'one\nTWO\nthree\nfour\n' > a.txt; loc; assert_has "⎇  main · pending +2/-1"
}
@test "untracked text files count their lines as pending additions" {
    printf 'x\ny\nz\n' > new.txt; loc; assert_has "pending +3"
}
@test "untracked binaries and files over 1 MB are not counted" {
    head -c 1500000 /dev/zero | tr '\0' 'a' > big.txt; printf '\x00\x01\x02\n' > blob.bin
    loc; assert_lacks "pending"
}
@test "gitignored files are not counted" {
    printf 'scratch.txt\n' > .gitignore; git add .gitignore; git commit -qm ignore
    printf 'a\nb\n' > scratch.txt; git push -q 2>/dev/null; loc; assert_lacks "pending"
}
@test "ahead of upstream: ↑N" {
    printf 'more\n' >> a.txt; git commit -qam more; loc; assert_has "⎇  main · ↑1"
}
@test "behind upstream: ↓N (as of the last fetch)" {
    local other="$BATS_TEST_TMPDIR/other"; git clone -q "$REMOTE" "$other"
    (cd "$other" && printf 'theirs\n' >> a.txt && git commit -qam theirs && git push -q 2>/dev/null)
    git fetch -q; loc; assert_has "↓1"
}
@test "pending and arrows share one cluster" {
    printf 'more\n' >> a.txt; git commit -qam more; printf 'edit\n' >> a.txt; loc
    assert_has "· pending +1 ↑1"
}
@test "a feature branch shows its diff vs the default branch" {
    git checkout -qb feature; printf 'f1\nf2\n' > f.txt; git add f.txt; git commit -qm feature
    loc; assert_has "⎇  feature" "· vs main +2"; assert_lacks "pending"
}
@test "the default branch is taken from origin/HEAD, falling back to main or master" {
    git remote set-head origin -d 2>/dev/null
    git checkout -qb feature; printf 'f1\n' > f.txt; git add f.txt; git commit -qm feature
    loc; assert_has "· vs main +1"
}
@test "a clone with only a feature branch compares against origin/<default>" {
    git checkout -qb feature; printf 'f1\n' > f.txt; git add f.txt; git commit -qm feature; git push -q -u origin feature 2>/dev/null
    local clone="$BATS_TEST_TMPDIR/clone"; git clone -q -b feature "$REMOTE" "$clone" 2>/dev/null
    (cd "$clone" && git remote set-head origin main 2>/dev/null && git branch -D main 2>/dev/null || true)
    DIR="$clone" loc; assert_has "⎇  feature" "vs main +1"
}
@test "a long branch name is capped at 24 characters plus .." {
    git checkout -qb feature/this-is-a-very-long-branch-name-indeed; loc
    assert_has "⎇  feature/this-is-a-very-l.."; assert_lacks "indeed"
}
@test "detached HEAD shows the short hash" {
    git checkout -q --detach; loc; assert_has "⎇  $(git rev-parse --short HEAD)"
}
@test "the remote's repo name appears when it differs from the directory name" {
    git remote set-url origin "$BATS_TEST_TMPDIR/renamed-upstream.git"; loc; assert_has "/project (renamed-upstream) ⎇  main"
}
@test "session churn from the input JSON: · session +A/-R" {
    ADDED=10 REMOVED=2 loc; assert_has "⎇  main · session +10/-2"
    ADDED=0 REMOVED=0 loc; assert_lacks "session"
}
@test "everything at once, in order: path, branch, pending, arrows, vs, session" {
    git checkout -qb feature; printf 'f1\n' > f.txt; git add f.txt; git commit -qm feature; git push -q -u origin feature 2>/dev/null
    printf 'f2\n' >> f.txt; git commit -qam f2; printf 'edit\n' >> a.txt
    ADDED=4 REMOVED=1 loc
    assert_has "⎇  feature · pending +1 ↑1 · vs main +2 · session +4/-1"
}
@test "the directory falls back to .cwd when workspace.current_dir is absent" {
    cd "$BATS_TEST_TMPDIR"   # not the repo itself, so the $PWD fallback can't mask a miss
    run bash -c 'printf "%s" "$0" | "$@" | sed "s/\x1b\[[0-9;]*m//g" | tail -1' "{\"cwd\":\"$REPO\"}" \
        env CLAUDE_CONFIG_DIR="$CFG" COLUMNS=120 CLAUDE_SPEND_DISPLAY=off bash "$SL"
    [[ "$output" == *"/project ⎇  main" ]] || { echo "got: $output"; false; }
}
@test "no origin/HEAD and no main: master is the default branch" {
    git remote set-head origin -d 2>/dev/null; git branch -m main master
    git checkout -qb feature; printf 'f1\n' > f.txt; git add f.txt; git commit -qm feature
    loc; assert_has "· vs master +1"
}

# --- the display file's repo-row names (config/display.conf) ---
# Everything on: a feature branch with an edit, a commit ahead of upstream,
# a diff against main and session churn.
busy() {
    if [ ! -e f.txt ]; then
        git checkout -qb feature; printf 'f1\n' > f.txt; git add f.txt; git commit -qm feature; git push -q -u origin feature 2>/dev/null
        printf 'f2\n' >> f.txt; git commit -qam f2; printf 'edit\n' >> a.txt
    fi
    ADDED=4 REMOVED=1 loc "$@"
}
# tail STR: the row ends with STR (the tmpdir path in front is long enough to be squeezed)
tail_is() { [[ "$output" == *"$1" ]] || { echo "got: $output"; echo "expected tail: $1"; return 1; }; }
@test "hide path: the row starts at the branch" {
    display_file "hide path"; busy; assert_equal "$output" "⎇  feature · pending +1 ↑1 · vs main +2 · session +4/-1"
}
@test "hide branch: the branch, its (repo) tag, pending, upstream and vs go; path and session stay" {
    busy; git remote set-url origin "$BATS_TEST_TMPDIR/renamed-upstream.git"
    display_file "hide branch"; busy; tail_is "/project · session +4/-1"; assert_lacks "renamed" "feature"
}
@test "hide pending, upstream, vs, session: each alone" {
    display_file "hide pending"; busy; tail_is "/project ⎇  feature · ↑1 · vs main +2 · session +4/-1"
    display_file "hide upstream"; busy; tail_is "/project ⎇  feature · pending +1 · vs main +2 · session +4/-1"
    display_file "hide vs"; busy; tail_is "/project ⎇  feature · pending +1 ↑1 · session +4/-1"
    display_file "hide session"; busy; tail_is "/project ⎇  feature · pending +1 ↑1 · vs main +2"
}
@test "hide pending and upstream together: no cluster, no stray dot" {
    display_file "hide pending upstream"; busy; tail_is "/project ⎇  feature · vs main +2 · session +4/-1"
}
@test "hide path and branch: only the session churn is left, with no leading dot" {
    display_file "hide path branch"; busy; assert_equal "$output" "· session +4/-1"
}
@test "hide repo: no row at all, even with churn" {
    display_file "hide repo"; git checkout -qb feature
    run bash -c 'printf "%s" "$0" | "$@" | sed "s/\x1b\[[0-9;]*m//g"' "{\"workspace\":{\"current_dir\":\"$REPO\"},\"cost\":{\"total_lines_added\":4}}" \
        env CLAUDE_CONFIG_DIR="$CFG" COLUMNS=120 CLAUDE_SPEND_DISPLAY="$CFG/display.conf" bash "$SL"
    assert_equal "$output" ""
}
@test "with the path and branch hidden git is not asked at all" {
    busy   # the fixture needs the real git
    mkdir -p "$BATS_TEST_TMPDIR/bin"; printf '#!/bin/sh\necho "$@" >> "%s/git.log"; exit 1\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/git"; chmod +x "$BATS_TEST_TMPDIR/bin/git"
    display_file "hide path branch"; busy PATH="$BATS_TEST_TMPDIR/bin:$PATH"; assert_equal "$output" "· session +4/-1"
    [ ! -e "$BATS_TEST_TMPDIR/git.log" ]
}
