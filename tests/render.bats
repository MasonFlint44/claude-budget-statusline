#!/usr/bin/env bats
# The budget line, rendered from a hand-written cache line. Cache line fields
# after "<date> <stamp>": <today$> <month$> <limit$> <workday-mask> <holiday doms...>
load helpers
setup() { fresh_config; }

# At NOW (Sat 09-05) on mon-fri, 17 workdays remain after today (Labor Day off):
# allowance = (400 - (120 - 3.25)) / 17 = 16.66 -> "$17"; 3.25 / 16.66 = 19.5 -> 20%.
@test "Saturday on a mon-fri week: off label, next workday's slice" {
    cache_line "$NOW" "3.25 120 400 1111100 7"; render "$NOW"
    assert_has "off:" " 20% " '$3.25/$17' "month:" " 30% " '$120/$400'; assert_lacks "day:"
}
# Seven-day week, Labor Day off: 25 days left incl. today -> 283.25 / 25 = 11.33 -> "$11"; 28.7 -> 29%.
@test "Saturday on a seven-day week: day label" {
    cache_line "$NOW" "3.25 120 400 1111111 7"; render "$NOW"
    assert_has "day:" " 29% " '$3.25/$11'; assert_lacks "off:"
}
@test "today listed as a holiday: off label, 25 days ahead" {
    cache_line "$NOW" "3.25 120 400 1111111 5"; render "$NOW"
    assert_has "off:" '$3.25/$11'
}
# Mon 09-14: 13 workdays left incl. today -> (400 - 100) / 13 = 23.08 -> "$23"; 20 / 23.08 = 86.7 -> 87%.
@test "a workday: today included in the count" {
    cache_line "2026-09-14 09:30:00" "20 120 400 1111100 7"; render "2026-09-14 09:30:00"
    assert_has "day:" " 87% " '$20/$23'
}
@test "budget clock: Fri 20:00 Chicago is still Friday locally" {
    cache_line "2026-09-04 20:00:00" "1 100 400 1111100 7"; render "2026-09-04 20:00:00"
    assert_has "day:"
}
@test "budget clock: the same instant is Saturday in Auckland" {
    cache_line "2026-09-04 20:00:00" "1 100 400 1111100 7" CLAUDE_BUDGET_TZ=Pacific/Auckland
    render "2026-09-04 20:00:00" CLAUDE_BUDGET_TZ=Pacific/Auckland
    assert_has "off:"
}
@test "month past the limit: pegged bar, overage tag, no day denominator" {
    cache_line "$NOW" "5 450 400 1111100 7"; render "$NOW"
    assert_has "month:" "113%" '$450/$400' '+$50' "off:" "999%" '$5.00 '; assert_lacks '$5.00/'
}
@test "month exactly at the limit with nothing spent today: day 0%, no overage" {
    cache_line "$NOW" "0 400 400 1111100 7"; render "$NOW"
    assert_has "off:" " 0% " '$0.00 ' "100%"; assert_lacks '+$'
}
@test "old cache format (no workday mask): bars hidden" {
    cache_line "$NOW" "3.25 120 400 7"; render "$NOW"
    assert_lacks "day:" "off:" "month:"; assert_has "ctx:"
}
@test "no limit known: bars hidden" {
    cache_line "$NOW" "3.25 120 0 1111100 7"; render "$NOW"
    assert_lacks "day:" "month:"
}
@test "yesterday's cache line: hidden, not misreported" {
    printf '%s %s 3.25 120 400 1111100 7\n' "$(at "$NOW" date -d yesterday +%F)" "$(epoch_at "$NOW")" > "$(cache_path)"
    render "$NOW"; assert_lacks "day:" "off:" "month:"
}
@test "garbled cache line: hidden" {
    printf '%s %s three 120 400 1111100 7\n' "$(at "$NOW" date +%F)" "$(epoch_at "$NOW")" > "$(cache_path)"
    render "$NOW"; assert_lacks "day:" "off:" "month:"
}
@test "no cache at all: bars hidden, rest renders" {
    render "$NOW"; assert_status 0; assert_has "Opus" "ctx:"; assert_lacks "day:" "month:"
}
@test "garbage on stdin: exit 0" {
    INPUT='not json' render "$NOW"; assert_status 0
}
@test "empty JSON: exit 0, empty first line" {
    INPUT='{}' render "$NOW"; assert_status 0; assert_lacks "ctx:" "Opus"
}
@test "last day of the month: denominator floors at 1" {
    # Wed 2026-09-30 with today's spend 10, month 390 of 400: remaining 20 / 1 workday.
    cache_line "2026-09-30 15:00:00" "10 390 400 1111100 7"; render "2026-09-30 15:00:00"
    assert_has "day:" " 50% " '$10/$20'
}
@test "Saturday on the last day of the month: no workday ahead, still floors at 1" {
    # Sat 2026-10-31: no workdays after it in October.
    cache_line "2026-10-31 15:00:00" "10 390 400 1111100 12"; render "2026-10-31 15:00:00"
    assert_has "off:" " 50% " '$10/$20'
}
@test "a cache line with no holidays field: every workday counts" {
    # 18 workdays after Saturday incl. Labor Day -> 283.25 / 18 = 15.74 -> "$16"; 3.25 / 15.74 = 20.6 -> 21%.
    cache_line "$NOW" "3.25 120 400 1111100"; render "$NOW"; assert_has "off:" " 21% " '$3.25/$16'
}
@test "the cached limit renders even when the override differs; the override lands at the next refresh" {
    cache_line "$NOW" "3.25 120 400 1111100 7"; render "$NOW" CLAUDE_BUDGET_MONTHLY_LIMIT=250; assert_has '$120/$400'
}
@test "a non-numeric limit in the cache: bars hidden unless the override supplies one" {
    cache_line "$NOW" "3.25 120 lots 1111100 7"; render "$NOW"; assert_lacks "month:"
    render "$NOW" CLAUDE_BUDGET_MONTHLY_LIMIT=250; assert_has '$120/$250'
}
@test "an unknown CLAUDE_BUDGET_TZ means UTC: Fri 20:00 Chicago is Saturday there" {
    cache_line "2026-09-04 20:00:00" "1 100 400 1111100 7" CLAUDE_BUDGET_TZ=Nowhere/Land
    render "2026-09-04 20:00:00" CLAUDE_BUDGET_TZ=Nowhere/Land; assert_has "off:"
}
@test "a context percentage in exponent form rounds like any other" {
    INPUT='{"context_window":{"used_percentage":1e-07}}' render "$NOW"; assert_status 0; assert_has "ctx:"; [[ "$output" == *" 0%" ]]
    INPUT='{"context_window":{"used_percentage":9.95e1}}' render "$NOW"; [[ "$output" == *" 100%" ]]
}
@test "null on stdin renders like an empty object" { INPUT='null' render "$NOW"; assert_status 0; assert_lacks "ctx:"; }

# --- the staleness tag: today's figures, but no successful fetch for a while ---
aged_cache() { printf '2026-09-05 %s 3.25 120 400 1111100 7\n' "$(( $(epoch_at "$NOW") - $1 ))" > "$(cache_path)"; }   # aged_cache SECONDS
@test "a cache under five minutes old carries no age tag" {
    aged_cache 299; render "$NOW" CLAUDE_BUDGET_REFRESH=600; assert_has "month:"; assert_lacks "·"
}
@test "at five minutes the age tag appears after the bars, in minutes" {
    aged_cache 300; render "$NOW" CLAUDE_BUDGET_REFRESH=600; [[ "$output" == *'$120/$400 ·5m' ]]
    aged_cache 754; render "$NOW" CLAUDE_BUDGET_REFRESH=900; [[ "$output" == *' ·12m' ]]
}
@test "from an hour on the tag counts hours" {
    aged_cache 3600; render "$NOW" CLAUDE_BUDGET_REFRESH=7200; [[ "$output" == *' ·1h' ]]
    aged_cache 11000; render "$NOW" CLAUDE_BUDGET_REFRESH=20000; [[ "$output" == *' ·3h' ]]
}
@test "the tag is dim and follows the overage tag when there is one" {
    printf '2026-09-05 %s 3.25 420 400 1111100 7\n' "$(( $(epoch_at "$NOW") - 600 ))" > "$(cache_path)"
    render "$NOW" CLAUDE_BUDGET_REFRESH=900; [[ "$output" == *'+$20 ·10m' ]]
    run _render_raw "$INPUT_DEFAULT" "$NOW" CLAUDE_BUDGET_REFRESH=900; assert_has $'\033[2m·10m\033[0m'
}
@test "no tag on the bare line when the budget bars are hidden" {
    printf '2026-09-05 %s 3.25 120 0 1111100 7\n' "$(( $(epoch_at "$NOW") - 600 ))" > "$(cache_path)"
    render "$NOW" CLAUDE_BUDGET_REFRESH=900; assert_lacks "month:" "·"
}
