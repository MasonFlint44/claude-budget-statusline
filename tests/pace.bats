#!/usr/bin/env bats
# The pace tick on the month bar: a light line on the cell that marks how far
# through the month's workdays today is, so fill short of it is under pace
# and fill past it is over. Position = workdays elapsed (today included) over
# the month's workdays, rounded onto a cell like the fill, clamped onto the
# last cell. September 2026 on mon-fri with Labor Day off: 21 workdays,
# Tue 09-01 is the first. Rendered at 60 columns, where every bar is at the
# ten-block floor: one block per 10%, tick = round(elapsed * 10 / total).
load helpers
setup() { fresh_config; }
month_bar() { [[ "$output" =~ month:([█░│]+\ [0-9]+%) ]] && printf '%s' "${BASH_REMATCH[1]}"; }
render10() { COLUMNS_OVERRIDE=60 render "$@"; }

@test "Saturday 09-05: four of 21 workdays elapsed, the tick on cell 3 inside a 30% fill" {
    cache_line "$NOW" "3.25 120 400 1111100 7"; render10 "$NOW"
    assert_equal "$(month_bar)" "██│░░░░░░░ 30%"
}
@test "the tick sits over the empty run when spend is behind pace" {
    cache_line "$NOW" "0 10 400 1111100 7"; render10 "$NOW"
    assert_equal "$(month_bar)" "░░│░░░░░░░ 3%"
}
@test "a mid-month workday: nine of 21 elapsed puts the tick on cell 5, past a 30% fill" {
    cache_line "2026-09-14 09:30:00" "20 120 400 1111100 7"; render10 "2026-09-14 09:30:00"
    assert_equal "$(month_bar)" "███░│░░░░░ 30%"
}
@test "the first workday: the tick on the first cell of an empty bar" {
    cache_line "2026-09-01 09:00:00" "0 0 400 1111100 7"; render10 "2026-09-01 09:00:00"
    assert_equal "$(month_bar)" "│░░░░░░░░░ 0%"
}
@test "the last workday: the tick clamps onto the final cell, a finish line the fill meets at the limit" {
    cache_line "2026-09-30 16:00:00" "0 400 400 1111100 7"; render10 "2026-09-30 16:00:00"
    assert_equal "$(month_bar)" "█████████│ 100%"
}
@test "over the limit: the fill pegs around the tick, which keeps its calendar position" {
    cache_line "$NOW" "5 450 400 1111100 7"; render10 "$NOW"
    assert_equal "$(month_bar)" "██│███████ 113%"; assert_has '+$50'
    cache_line "2026-09-30 16:00:00" "5 450 400 1111100 7"; render10 "2026-09-30 16:00:00"
    assert_equal "$(month_bar)" "█████████│ 113%"
}
@test "a seven-day week counts weekends as elapsed: Sun 09-20 is 19 of 29 there, 13 of 21 on mon-fri" {
    cache_line "2026-09-20 12:00:00" "20 120 400 1111111 7"; render10 "2026-09-20 12:00:00"
    assert_equal "$(month_bar)" "███░░░░│░░ 30%"
    cache_line "2026-09-20 12:00:00" "20 120 400 1111100 7"; render10 "2026-09-20 12:00:00"
    assert_equal "$(month_bar)" "███░░░│░░░ 30%"
}
@test "a holiday counts as neither elapsed nor total: Tue 09-08 is 5 of 21 with Labor Day listed, 6 of 22 without" {
    cache_line "2026-09-08 09:30:00" "0 120 400 1111100 7"; render10 "2026-09-08 09:30:00"
    assert_equal "$(month_bar)" "██│░░░░░░░ 30%"
    cache_line "2026-09-08 09:30:00" "0 120 400 1111100"; render10 "2026-09-08 09:30:00"
    assert_equal "$(month_bar)" "███│░░░░░░ 30%"
}
@test "the spend clock places the tick: Sun 20:00 in Chicago is Monday in Auckland, one more workday elapsed" {
    cache_line "2026-09-20 20:00:00" "1 100 400 1111100 7"; render10 "2026-09-20 20:00:00"
    assert_equal "$(month_bar)" "███░░░│░░░ 25%"   # 13 of 21
    cache_line "2026-09-20 20:00:00" "1 100 400 1111100 7" CLAUDE_SPEND_TZ=Pacific/Auckland
    render10 "2026-09-20 20:00:00" CLAUDE_SPEND_TZ=Pacific/Auckland
    assert_equal "$(month_bar)" "███░░░░│░░ 25%"   # 14 of 21
}
@test "a month with no workdays at all has no tick" {
    cache_line "$NOW" "3.25 120 400 0000000 7"; render10 "$NOW"
    assert_has "month:"; assert_lacks "│"
}
@test "only the month bar carries a tick; the tick replaces a cell, so the bar keeps its width" {
    cache_line "$NOW" "3.25 120 400 1111100 7"; render10 "$NOW"
    [[ "$output" =~ ctx:([█░]+)\ 12% ]]; assert_equal "${#BASH_REMATCH[1]}" 10
    [[ "$output" =~ off:([█░]+)\ 20% ]]; assert_equal "${#BASH_REMATCH[1]}" 10
    [[ "$output" =~ month:([█░│]+)\ 30% ]]; assert_equal "${#BASH_REMATCH[1]}" 10
}
