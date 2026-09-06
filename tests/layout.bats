#!/usr/bin/env bats
# Widths and the first-line pieces: bars share one width and fill the row,
# the row splits in two when even floor-width bars can't fit, and the model,
# effort, context and session-cost pieces format as documented.
load helpers
setup() { fresh_config; cache_line "$NOW" "3.25 120 400 1111100 7"; }
FULL='{"model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":42.6},"cost":{"total_cost_usd":1234.5},"workspace":{"current_dir":"/tmp"}}'
# bar_width LINE LABEL -> number of block characters in the bar after LABEL
bar_width() { [[ "$1" =~ $2([█░│]+) ]] && printf '%s' "${#BASH_REMATCH[1]}"; }
# all_bars_equal LINE... -> every bar on the given rows has the same width
all_bars_equal() {
    local w="" row lbl
    for row in "$@"; do for lbl in ctx: day: off: month:; do
        case "$row" in *"$lbl"*) [ -z "$w" ] && w=$(bar_width "$row" "$lbl"); [ "$(bar_width "$row" "$lbl")" = "$w" ] || { echo "bar widths differ on: $row"; return 1; } ;; esac
    done; done
}
at_width() { INPUT="$FULL" COLUMNS_OVERRIDE="$1" render "$NOW"; }

@test "200 columns: one row, three bars stretched to 41 blocks, fits the reserve" {
    at_width 200; [ "${#lines[@]}" = 1 ]
    assert_equal "$(bar_width "${lines[0]}" ctx:)" 41; all_bars_equal "${lines[@]}"
    [ "${#lines[0]}" -le 195 ]
}
@test "120 columns: one row, 15 blocks" {
    at_width 120; [ "${#lines[@]}" = 1 ]; assert_equal "$(bar_width "${lines[0]}" ctx:)" 15; all_bars_equal "${lines[@]}"; [ "${#lines[0]}" -le 115 ]
}
@test "100 columns: two rows, bars widen to 28 and still match across rows" {
    at_width 100; [ "${#lines[@]}" = 2 ]
    assert_has "Opus · high | ctx:"; [[ "${lines[1]}" == off:* ]]
    assert_equal "$(bar_width "${lines[0]}" ctx:)" 28; all_bars_equal "${lines[@]}"
    [ "${#lines[0]}" -le 95 ] && [ "${#lines[1]}" -le 95 ]
}
@test "60 columns: two rows at the ten-block floor" {
    at_width 60; [ "${#lines[@]}" = 2 ]; assert_equal "$(bar_width "${lines[1]}" month:)" 10; all_bars_equal "${lines[@]}"
}
@test "40 columns: too narrow even for the floor; floor-width bars overflow rather than shrink" {
    at_width 40; [ "${#lines[@]}" = 2 ]; assert_equal "$(bar_width "${lines[1]}" month:)" 10; [ "${#lines[1]}" -gt 35 ]
}
@test "30 and 20 columns: still two rows at the floor, nothing dropped" {
    at_width 30; [ "${#lines[@]}" = 2 ]; assert_has "Opus · high" "ctx:" "off:" "month:"; assert_equal "$(bar_width "${lines[1]}" month:)" 10
    at_width 20; [ "${#lines[@]}" = 2 ]; assert_equal "$(bar_width "${lines[1]}" month:)" 10; all_bars_equal "${lines[@]}"
}
@test "the age tag is part of the row's width: bars shrink to make room, the row still fits" {
    printf '2026-09-05 %s 3.25 120 400 1111100 7\n' "$(( $(epoch_at "$NOW") - 600 ))" > "$(cache_path)"
    INPUT="$FULL" COLUMNS_OVERRIDE=120 render "$NOW" CLAUDE_BUDGET_REFRESH=900
    [ "${#lines[@]}" = 1 ]; [[ "${lines[0]}" == *' ·10m' ]]; [ "${#lines[0]}" -le 115 ]
    assert_equal "$(bar_width "${lines[0]}" ctx:)" 13; all_bars_equal "${lines[@]}"
    INPUT="$FULL" COLUMNS_OVERRIDE=100 render "$NOW" CLAUDE_BUDGET_REFRESH=900
    [ "${#lines[@]}" = 2 ]; [[ "${lines[1]}" == *' ·10m' ]]; [ "${#lines[1]}" -le 95 ]; all_bars_equal "${lines[@]}"
}
@test "two rows without a ctx bar: the model alone on row 1, the budget row sets the width" {
    INPUT='{"model":{"display_name":"Opus"}}' COLUMNS_OVERRIDE=40 render "$NOW"
    [ "${#lines[@]}" = 2 ]; assert_equal "${lines[0]}" "Opus"; [[ "${lines[1]}" == off:* ]]; all_bars_equal "${lines[@]}"
}
@test "too narrow with only a ctx bar: it stays beside the model (row 1 owns it) at the floor width" {
    rm -f "$(cache_path)"
    INPUT='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":50}}' COLUMNS_OVERRIDE=24 render "$NOW"
    [ "${#lines[@]}" = 1 ]; assert_equal "${lines[0]}" "Opus | ctx:█████░░░░░ 50%"
}
@test "COLUMNS unset and no tty: 80-column fallback, two rows of 18" {
    at_width 0; [ "${#lines[@]}" = 2 ]; assert_equal "$(bar_width "${lines[0]}" ctx:)" 18
}
@test "the tighter row sets the shared width when the rows split" {
    # Row 2 carries two bars plus money; row 1 one bar. Both end up at row 2's width.
    at_width 90; assert_equal "$(bar_width "${lines[0]}" ctx:)" "$(bar_width "${lines[1]}" month:)"
}

# --- pieces ---
@test "model and effort: 'Opus · high'" { at_width 120; assert_has "Opus · high | "; }
@test "no effort: no dot" { INPUT='{"model":{"display_name":"Opus"}}' render "$NOW"; assert_has "Opus"; assert_lacks "·"; }
@test "each effort level renders its name" {
    local l; for l in low medium high xhigh max; do
        INPUT="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"$l\"}}" render "$NOW"; assert_has "Opus · $l"
    done
}
@test "context percent rounds: 42.6 -> 43%" { at_width 120; assert_has "ctx:" " 43% "; }
@test "context percent rounds half up: 12.5 -> 13%, 12.49 -> 12%" {
    INPUT='{"context_window":{"used_percentage":12.5}}' render "$NOW"; assert_has " 13% "
    INPUT='{"context_window":{"used_percentage":12.49}}' render "$NOW"; assert_has " 12% "
}
@test "money rounds half up too: \$12.345 -> \$12.35, \$14.5 -> \$15, \$1250 -> \$1.3k" {
    INPUT='{"context_window":{"used_percentage":1},"cost":{"total_cost_usd":9.345}}' render "$NOW"; assert_has '$9.35'
    INPUT='{"context_window":{"used_percentage":1},"cost":{"total_cost_usd":14.5}}' render "$NOW";  assert_has '$15 '
    INPUT='{"context_window":{"used_percentage":1},"cost":{"total_cost_usd":1250}}' render "$NOW";  assert_has '$1.3k'
}
@test "no context figure: no ctx bar" { INPUT='{"model":{"display_name":"Opus"}}' render "$NOW"; assert_lacks "ctx:"; }
@test "session cost formats by magnitude: \$1.50, \$15, \$1.2k" {
    INPUT='{"context_window":{"used_percentage":1},"cost":{"total_cost_usd":1.5}}' render "$NOW";   assert_has '$1.50'
    INPUT='{"context_window":{"used_percentage":1},"cost":{"total_cost_usd":15.4}}' render "$NOW";  assert_has '$15 '
    INPUT='{"context_window":{"used_percentage":1},"cost":{"total_cost_usd":1234.5}}' render "$NOW"; assert_has '$1.2k'
    INPUT='{"context_window":{"used_percentage":1},"cost":{"total_cost_usd":0}}' render "$NOW";     assert_has '$0.00'
}
@test "session cost needs the ctx bar to hang on" {
    INPUT='{"model":{"display_name":"Opus"},"cost":{"total_cost_usd":1.5}}' render "$NOW"; assert_lacks '$1.50'
}
@test "budget money formats by magnitude too: \$1.2k of \$5.0k" {
    cache_line "$NOW" "1234 1800 5000 1111100 7"; render "$NOW"; assert_has '$1.8k/$5.0k' '$1.2k/'
}
@test "budget bars alone: no model, no ctx" {
    INPUT='{}' render "$NOW"; [ "${#lines[@]}" = 1 ]; [[ "${lines[0]}" == off:* ]]; assert_has "month:"
}
@test "the repo line is on with no display file and off with hide repo" {
    run _render "$FULL" "$NOW" CLAUDE_BUDGET_DISPLAY=off; [ "${#lines[@]}" = 2 ]; assert_has "/tmp"
    run _render "$FULL" "$NOW"; [ "${#lines[@]}" = 1 ]
}
@test "a percentage past 999 pegs the label" {
    cache_line "$NOW" "50 5000 400 1111100 7"; render "$NOW"; assert_has "month:" " 999% "
}
