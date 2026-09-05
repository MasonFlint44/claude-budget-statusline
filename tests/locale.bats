#!/usr/bin/env bats
# A comma-decimal locale must not break the percent and money formatting:
# the script folds LC_ALL into LC_CTYPE/LC_TIME and pins LC_NUMERIC=C.
# Skipped when the machine has no such locale (CI generates de_DE.UTF-8).
load helpers
setup() {
    fresh_config; cache_line "$NOW" "3.25 120 400 1111100 7"
    LOC=$(locale -a 2>/dev/null | grep -m1 -iE '^de_DE\.utf-?8$') || true
    [ -n "$LOC" ] || skip "no de_DE.UTF-8 locale on this machine"
}
INPUT_PCT='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42.6},"cost":{"total_cost_usd":1.5}}'
check() { assert_status 0; assert_has " 43% " '$1.50' " 19% " '$3.25/$17' " 30% " '$120/$400'; }

@test "LC_ALL=de_DE.UTF-8" { INPUT="$INPUT_PCT" render "$NOW" LC_ALL="$LOC"; check; }
@test "LC_NUMERIC=de_DE.UTF-8 alone" { INPUT="$INPUT_PCT" render "$NOW" LC_ALL= LC_NUMERIC="$LOC"; check; }
@test "LANG=de_DE.UTF-8 alone" { INPUT="$INPUT_PCT" render "$NOW" LC_ALL= LANG="$LOC"; check; }
@test "the calendar listing under LC_ALL=de_DE.UTF-8 keeps English day names and ASCII dates" {
    run at "$NOW" env LC_ALL="$LOC" CLAUDE_BUDGET_CALENDAR="$SHIPPED" bash "$SL" --calendar 2026
    assert_status 0; assert_has "2026-07-03 Fri Independence Day" "September 2026: 21 workdays"
}
