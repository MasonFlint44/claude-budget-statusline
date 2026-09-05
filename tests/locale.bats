#!/usr/bin/env bats
# A comma-decimal locale must not break the percent and money formatting:
# the script folds LC_ALL into LC_CTYPE/LC_TIME and pins LC_NUMERIC=C.
# Skipped when the machine has no such locale (CI generates de_DE.UTF-8).
load helpers
# Build the locale once per file into the file's tmpdir with localedef (no
# root needed) and hand it to every child through LOCPATH, so the tests run
# on any machine with the glibc locale sources (package "locales").
setup_file() {
    export LOCPATH="$BATS_FILE_TMPDIR/locales"; mkdir -p "$LOCPATH"
    localedef -i de_DE -f UTF-8 "$LOCPATH/de_DE.UTF-8" >/dev/null 2>&1 || true
}
setup() {
    fresh_config; cache_line "$NOW" "3.25 120 400 1111100 7"
    LOC=de_DE.UTF-8
    [ "$(LC_ALL=$LOC date -d 2026-09-05 +%a 2>/dev/null)" = Sa ] || skip "could not build de_DE.UTF-8 (apt install locales)"
}
INPUT_PCT='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42.6},"cost":{"total_cost_usd":1.5}}'
check() { assert_status 0; assert_has " 43% " '$1.50' " 20% " '$3.25/$17' " 30% " '$120/$400'; }

@test "LC_ALL=de_DE.UTF-8" { INPUT="$INPUT_PCT" render "$NOW" LC_ALL="$LOC"; check; }
@test "LC_NUMERIC=de_DE.UTF-8 alone" { INPUT="$INPUT_PCT" render "$NOW" LC_ALL= LC_NUMERIC="$LOC"; check; }
@test "LANG=de_DE.UTF-8 alone" { INPUT="$INPUT_PCT" render "$NOW" LC_ALL= LANG="$LOC"; check; }
@test "the calendar listing under LC_ALL=de_DE.UTF-8 keeps English day names and ASCII dates" {
    run at "$NOW" env LC_ALL="$LOC" CLAUDE_BUDGET_CALENDAR="$SHIPPED" bash "$SL" --calendar 2026
    assert_status 0; assert_has "2026-07-03 Fri Independence Day" "September 2026: 21 workdays"
}
