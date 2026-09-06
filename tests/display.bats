#!/usr/bin/env bats
# The display file (config/display.conf): which elements render. Each name
# hidden alone, dependents following their parent, the row re-flowing around
# a hidden piece, the fetch skipped when both budget bars are hidden, the
# file's parsing, and the --display listing as goldens.
load helpers
setup() { fresh_config; }
# A render with every first-line element on screen: model + effort, ctx bar
# + cost + a warm cache cue, day (a Saturday: "off:") + month bars with the
# pace tick, and an age tag from a cache ten and a half minutes old (·10m
# whichever way the fake clock jitters; no refresh: the interval is longer).
FULL='{"model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":42.6},"cost":{"total_cost_usd":3.72},"prompt_cache":{"caching_observed":true,"warm":true,"ttl":"1h","expires_at":%s},"workspace":{"current_dir":"/tmp"}}'
full() {   # full [LINE...]: render FULL with a display file of those lines
    [ $# -gt 0 ] && display_file "$@"
    printf '2026-09-05 %s 3.25 120 400 1111100 7\n' "$(( $(epoch_at "$NOW") - 630 ))" > "$(cache_path)"
    INPUT="$(printf "$FULL" "$(( $(epoch_at "$NOW") + 2500 ))")" render "$NOW" CLAUDE_BUDGET_REFRESH=900
}
ALL=("Opus · high" "ctx:" '$3.72' "· cache 42m" "off:" '$3.25/' "month:" '/$400' "│" "·10m")
bar_width() { [[ "$1" =~ $2([█░│]+) ]] && printf '%s' "${#BASH_REMATCH[1]}"; }

@test "no display file: every element shows, the repo row included" {
    full "# nothing hidden"; assert_has "${ALL[@]}" "/tmp"
}
@test "hide model: the model and the effort that hangs off it" {
    full "hide model"; assert_lacks "Opus" "high"; assert_has "ctx:" '$3.72' "cache 42m" "off:" "month:" "│" "·10m"
}
@test "hide effort: the model stays" {
    full "hide effort"; assert_lacks "high"; assert_has "Opus | ctx:" "cache 42m" "off:" "month:"
}
@test "hide ctx: the bar, the cost and the cache cue go" {
    full "hide ctx"; assert_lacks "ctx:" '$3.72' "cache"; assert_has "Opus · high | off:" "month:" "│" "·10m"
}
@test "hide cost: the cache cue follows the percentage directly" {
    full "hide cost"; assert_lacks '$3.72'; assert_has "43% · cache 42m" "off:" "month:"
}
@test "hide cache: the cost stays" {
    full "hide cache"; assert_lacks "cache"; assert_has '43% $3.72' "off:" "month:"
}
@test "hide day: the month bar alone carries the tick and the age tag" {
    full "hide day"; assert_lacks "off:" "day:" '$3.25'; assert_has "| month:" "│" '/$400 ·10m' "ctx:"
}
@test "hide month: the day bar alone; the tick and the overage go with it" {
    full "hide month"; assert_lacks "month:" '$400' "│"; assert_has "off:" '$3.25/' "·10m"
    printf '2026-09-05 %s 3.25 420 400 1111100 7\n' "$(( $(epoch_at "$NOW") - 630 ))" > "$(cache_path)"
    INPUT="$(printf "$FULL" 0)" render "$NOW" CLAUDE_BUDGET_REFRESH=900; assert_lacks '+$20' "month:"
}
@test "hide pace: the month bar without its tick" {
    full "hide pace"; assert_lacks "│"; assert_has "month:" '/$400' "off:"
}
@test "hide age: the stale tag goes, the figures stay" {
    full "hide age"; assert_lacks "·10m"; assert_has "off:" "month:" '/$400'
}
@test "hide repo: no second row" {
    full "hide repo"; assert_lacks "/tmp"; assert_has "${ALL[@]}"
}
@test "hiding everything on the first line leaves just the repo row" {
    full "hide model ctx day month"; assert_equal "$output" "/tmp"
}
@test "hiding everything renders nothing" {
    full "hide model ctx day month repo"; assert_equal "$output" ""
}

# --- the row re-flows around what is hidden ---
@test "hiding the cost and the cache widens the bars (200 columns: 36 to 42 blocks)" {
    COLUMNS_OVERRIDE=200 full "# all on"; [ "${#lines[@]}" = 2 ]; assert_equal "$(bar_width "${lines[0]}" ctx:)" 36
    COLUMNS_OVERRIDE=200 full "hide cost cache"; [ "${#lines[@]}" = 2 ]; assert_equal "$(bar_width "${lines[0]}" ctx:)" 42
}
@test "at 120 columns the full line takes two rows; hiding the cost and cache fits it in one" {
    full "# all on"; [ "${#lines[@]}" = 3 ]; [[ "${lines[1]}" == off:* ]]; assert_equal "${lines[2]}" /tmp
    full "hide cost cache"; [ "${#lines[@]}" = 2 ]; [[ "${lines[0]}" == "Opus · high | ctx:"*"| off:"* ]]; assert_equal "${lines[1]}" /tmp
}
@test "hiding ctx leaves the budget bars as the only bars, sharing the row's width" {
    full "hide ctx"; [ "${#lines[@]}" = 2 ]; [[ "${lines[0]}" == "Opus · high | off:"* ]]
    assert_equal "$(bar_width "${lines[0]}" off:)" 28; assert_equal "$(bar_width "${lines[0]}" month:)" 28
}

# --- both budget bars hidden: no fetch at all ---
@test "hide day and month: no credentials read, no request, no cache, no lock, no baseline" {
    fetch_setup; display_file "hide day month"
    render "$NOW"; sleep 0.3
    assert_lacks "day:" "off:" "month:"; assert_has "ctx:"
    assert_equal "$(curl_calls)" 0
    [ ! -e "$(cache_path)" ]; [ ! -d "$CFG/cache/statusline/budget-usage.lock" ]; [ ! -e "$DAYSTART" ]; [ ! -e "$HOLD" ]
}
@test "hide day and month with a usable cache: still no refresh, bars hidden" {
    fetch_setup; display_file "hide day month"
    printf '2026-09-05 1 3.25 120 400 1111100 7\n' > "$(cache_path)"   # ancient: would refresh
    render "$NOW"; sleep 0.3; assert_equal "$(curl_calls)" 0; assert_lacks "month:"
    assert_equal "$(cache_contents)" "2026-09-05 1 3.25 120 400 1111100 7"
}
@test "hiding only one of the two still fetches" {
    fetch_setup; display_file "hide day"; refresh "$NOW"; assert_equal "$(curl_calls)" 1
    render "$NOW"; assert_has "month:"; assert_lacks "off:"
}
@test "--doctor with day and month hidden: says so, exits 0, fetches nothing" {
    fetch_setup; display_file "hide day month"
    run at "$NOW" env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_BUDGET_DISPLAY="$CFG/display.conf" bash "$SL" --doctor
    assert_status 0; assert_has "display:      $CFG/display.conf: hidden day, month, pace, age" "bars:         hidden by $CFG/display.conf (day and month both hidden), so nothing is fetched"
    assert_lacks "credentials:"; assert_equal "$(curl_calls)" 0
}

# --- the doctor's display line ---
doctor() { run at "$NOW" env CLAUDE_CONFIG_DIR="$CFG" "$@" bash "$SL" --doctor; }
@test "--doctor names the display file and what it hides, with unparsed lines counted" {
    fetch_setup; display_file "hide pace cache" "hide foo"
    doctor CLAUDE_BUDGET_DISPLAY="$CFG/display.conf"; assert_status 0
    assert_has "display:      $CFG/display.conf: hidden cache, pace, 1 line(s) not parsed (see --display)" "bars:         will show"
}
@test "--doctor with nothing hidden, no file, or the knob off" {
    fetch_setup; display_file "# empty"
    doctor CLAUDE_BUDGET_DISPLAY="$CFG/display.conf"; assert_has "display:      $CFG/display.conf: all elements shown"
    doctor CLAUDE_BUDGET_DISPLAY=/nope; assert_has "display:      no file at /nope: all elements shown"
    doctor CLAUDE_BUDGET_DISPLAY=off; assert_has "display:      off (CLAUDE_BUDGET_DISPLAY=off): all elements shown"
}

# --- the file and the knob ---
@test "CLAUDE_BUDGET_DISPLAY: off, none, no, 0, false (any case) mean no file; a missing file hides nothing" {
    local v; for v in off none no 0 false OFF None /nope; do
        INPUT="$(printf "$FULL" 0)" render "$NOW" CLAUDE_BUDGET_DISPLAY="$v"; assert_has "Opus" "/tmp"
    done
}
@test "the shipped display.conf hides nothing" {
    run bash "$SL" --display; assert_status 0; assert_has "display: $(cd "$TESTS_DIR/../statusline/config" && pwd)/display.conf"
    [ "$(printf '%s\n' "$output" | grep -c '^[a-z]*  *on  ')" = 16 ]; assert_lacks " off"
}
@test "an unreadable file hides nothing" {
    [ "$(id -u)" != 0 ] || skip "root reads everything"
    display_file "hide model"; chmod 000 "$CFG/display.conf"; full; assert_has "Opus"
}
@test "names are case-insensitive, comma or space separated; comments, CRLF and a BOM are fine" {
    full $'\xef\xbb\xbfhide PACE,Cache\r' $'  hide  age # not now\r'; assert_lacks "│" "cache" "·10m"; assert_has "Opus · high" "month:"
}
@test "hides accumulate across lines" {
    full "hide pace" "hide cache" "hide pace"; assert_lacks "│" "cache"
}
@test "bad lines: the good names on the line still apply, and the render stays silent" {
    display_file "hide pace foo" "show model" "hide"
    printf '2026-09-05 %s 3.25 120 400 1111100 7\n' "$(( $(epoch_at "$NOW") - 630 ))" > "$(cache_path)"
    run --separate-stderr _render "$(printf "$FULL" 0)" "$NOW" CLAUDE_BUDGET_REFRESH=900
    assert_lacks "│"; assert_has "Opus" "month:"; assert_equal "$stderr" ""
}

# --- the --display listing ---
# display_golden NAME: compare `--display $CFG/display.conf` with tests/expected/NAME.txt
display_golden() {
    local actual
    run --separate-stderr at "$NOW" bash "$SL" --display "$CFG/display.conf"; assert_status 0
    actual=$(printf '%s\n--- stderr\n%s\n' "$output" "$stderr" | sed "s#$CFG/#<cfg>/#g")
    if [ -n "${UPDATE:-}" ]; then printf '%s\n' "$actual" > "$EXP/$1.txt"; return 0; fi
    [ -r "$EXP/$1.txt" ] || { echo "no golden $EXP/$1.txt (run with UPDATE=1)"; return 1; }
    diff -u "$EXP/$1.txt" <(printf '%s\n' "$actual") || return 1
}
@test "--display: everything on" { display_file "# a file that hides nothing"; display_golden display-all; }
@test "--display: a mixed file, dependents reported as off (needs X)" {
    display_file "hide ctx" "hide month" "hide branch" "hide session"; display_golden display-mixed
}
@test "--display: day and month hidden take the age tag; repo takes the whole row" {
    display_file "hide day, month" "hide repo"; display_golden display-repo
}
@test "--display: bad lines are reported on stderr, the good names apply" {
    display_file "hide pace foo" "show model" "hide" "hide Cache,bar,vs"; display_golden display-bad
}
@test "--display with no file, or the knob off" {
    run at "$NOW" bash "$SL" --display /nope; assert_status 0; assert_has "display: no file at /nope: everything shown"
    run at "$NOW" env CLAUDE_BUDGET_DISPLAY=off bash "$SL" --display; assert_status 0; assert_has "display: off (CLAUDE_BUDGET_DISPLAY=off): everything shown"
    run at "$NOW" bash "$SL" --display none; assert_has "display: off (--display none): everything shown"
}
@test "--display reads nothing from stdin" {
    run timeout 10 bash -c "cd '$TESTS_DIR' && . helpers.bash && at '$NOW' bash '$SL' --display" <&-; assert_status 0; assert_has "model     on"
}
