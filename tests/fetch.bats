#!/usr/bin/env bats
# refresh_usage through the fake curl: the request, the response shapes, the
# day-start baseline, limit precedence, and every failure's hold.
load helpers
setup() { fetch_setup; }
STAMP=""; setup_stamp() { STAMP=$(epoch_at "$NOW"); }

@test "request: the usage URL, the bearer token in a piped config, never in argv" {
    refresh "$NOW"
    run cat "$FAKE_CURL_LOG"
    assert_has 'url = "https://api.anthropic.com/api/oauth/usage"' 'header = "Authorization: Bearer tok-123"' 'anthropic-beta: oauth-2025-04-20' '-K -'
    assert_lacks 'argv:.*tok-123'
    run grep -- '^--- argv:' "$FAKE_CURL_LOG"; assert_lacks 'tok-123'
}
@test "success: cache line = date, stamp, day, month, limit, mask, holidays" {
    setup_stamp; refresh "$NOW"
    read -r c_date c_stamp c_rest < "$(cache_path)"
    assert_equal "$c_date" "2026-09-05"; assert_near "$c_stamp" "$STAMP"; assert_equal "$c_rest" "0 120 400 1111100 7"
    [ ! -e "$HOLD" ]
}
@test "first sighting of a day pins the month total as the baseline" {
    refresh "$NOW"; assert_equal "$(cat "$DAYSTART")" "2026-09-05 120"
}
@test "daily = month minus the day's baseline" {
    printf '2026-09-05 100\n' > "$DAYSTART"; refresh "$NOW"
    run cache_contents; assert_has " 20 120 400 "
}
@test "a new day re-pins the baseline" {
    printf '2026-09-04 100\n' > "$DAYSTART"; refresh "$NOW"
    assert_equal "$(cat "$DAYSTART")" "2026-09-05 120"; run cache_contents; assert_has " 0 120 400 "
}
@test "month rollover (month total below the baseline) re-pins" {
    printf '2026-09-05 500\n' > "$DAYSTART"; refresh "$NOW"
    assert_equal "$(cat "$DAYSTART")" "2026-09-05 120"; run cache_contents; assert_has " 0 120 400 "
}
@test "the spend clock names the day: Auckland is already the 6th" {
    refresh "$NOW" CLAUDE_SPEND_TZ=Pacific/Auckland
    [[ "$(cache_contents)" == 2026-09-06\ * ]] || { echo "cache: $(cache_contents)"; false; }
    assert_equal "$(cut -d' ' -f1 "$DAYSTART")" "2026-09-06"
}
@test "the second render shows the fetched numbers" {
    refresh "$NOW"; assert_lacks "month:"          # the first render had no cache yet
    render "$NOW"; assert_has "off:" "month:" " 30% " '$120/$400'
}
@test "CLAUDE_SPEND_MONTHLY_LIMIT overrides the org limit" {
    refresh "$NOW" CLAUDE_SPEND_MONTHLY_LIMIT=250; run cache_contents; assert_has " 120 250 "
    render "$NOW"; assert_has '$120/$250' " 48% "
}
@test "a non-numeric override is ignored" {
    refresh "$NOW" CLAUDE_SPEND_MONTHLY_LIMIT=lots; run cache_contents; assert_has " 120 400 "
}
@test "no limit in the response and no override: limit 0, bars hidden" {
    FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":12000}}}' refresh "$NOW"
    run cache_contents; assert_has " 120 0 "
    render "$NOW"; assert_lacks "month:" "day:" "off:"
}
@test "no limit in the response but an override: the override is the limit" {
    FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":12000}}}' refresh "$NOW" CLAUDE_SPEND_MONTHLY_LIMIT=300
    run cache_contents; assert_has " 120 300 "
}
@test "spend.cap.credits is the fallback limit field" {
    FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":12000},"cap":{"credits":{"amount_minor":30000}}}}' refresh "$NOW"
    run cache_contents; assert_has " 120 300 "
}
@test "fractional dollars survive: 1234 minor units = 12.34" {
    FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":1234},"limit":{"amount_minor":40000}}}' refresh "$NOW"
    run cache_contents; assert_has " 12.34 400 "
}
@test "the calendar's mask and this month's holidays ride in the cache line" {
    refresh "$NOW" CLAUDE_SPEND_CALENDAR="$CAL/sun-thu.conf"
    run cache_contents; assert_has " 1111001 3 12 14 15 16 17 18 19 20 "
}
@test "no dollar figure in the response: hold one interval, no cache" {
    setup_stamp; FAKE_CURL_BODY='{"organization":{}}' refresh "$NOW"
    [ ! -e "$(cache_path)" ]; assert_near "$(cat "$HOLD")" "$(( STAMP + 60 ))"
}
@test "empty body: hold one interval" {
    setup_stamp; FAKE_CURL_BODY='' refresh "$NOW"
    [ ! -e "$(cache_path)" ]; assert_near "$(cat "$HOLD")" "$(( STAMP + 60 ))"
}
@test "HTTP 429: hold five minutes" {
    setup_stamp; FAKE_CURL_CODE=429 refresh "$NOW"
    [ ! -e "$(cache_path)" ]; assert_near "$(cat "$HOLD")" "$(( STAMP + 300 ))"
}
@test "HTTP 500 with an error body: hold one interval" {
    setup_stamp; FAKE_CURL_CODE=500 FAKE_CURL_BODY='{"error":"boom"}' refresh "$NOW"
    [ ! -e "$(cache_path)" ]; assert_near "$(cat "$HOLD")" "$(( STAMP + 60 ))"
}
@test "transport failure: hold one interval" {
    setup_stamp; FAKE_CURL_EXIT=7 refresh "$NOW"
    [ ! -e "$(cache_path)" ]; assert_near "$(cat "$HOLD")" "$(( STAMP + 60 ))"
}
@test "the hold honours CLAUDE_SPEND_REFRESH" {
    setup_stamp; FAKE_CURL_EXIT=7 refresh "$NOW" CLAUDE_SPEND_REFRESH=120
    assert_near "$(cat "$HOLD")" "$(( STAMP + 120 ))"
}
@test "a failure keeps the previous day's cache untouched" {
    printf '2026-09-04 1 3.25 120 400 1111100 7\n' > "$(cache_path)"
    FAKE_CURL_EXIT=7 refresh "$NOW"
    assert_equal "$(cache_contents)" "2026-09-04 1 3.25 120 400 1111100 7"
}
@test "success clears a leftover hold" {
    printf '1\n' > "$HOLD"; refresh "$NOW"; [ ! -e "$HOLD" ]
}
@test "no credentials file: hold, curl never called" {
    rm -f "$CREDS"; refresh "$NOW"; [ -e "$HOLD" ]; assert_equal "$(curl_calls)" 0
}
@test "credentials without a token: hold, curl never called" {
    printf '{"claudeAiOauth":{}}\n' > "$CREDS"; refresh "$NOW"; [ -e "$HOLD" ]; assert_equal "$(curl_calls)" 0
}
@test "unreadable credentials JSON: hold, curl never called" {
    printf 'nope\n' > "$CREDS"; refresh "$NOW"; [ -e "$HOLD" ]; assert_equal "$(curl_calls)" 0
}
@test "expired token: hold, curl never called" {
    creds "$NOW" -1; refresh "$NOW"; [ -e "$HOLD" ]; assert_equal "$(curl_calls)" 0
}
@test "token expiring in one second is still used" {
    creds "$NOW" 1; refresh "$NOW"; assert_equal "$(curl_calls)" 1; [ -e "$(cache_path)" ]
}
@test "no expiry field: try anyway" {
    creds "$NOW" none; refresh "$NOW"; assert_equal "$(curl_calls)" 1; [ -e "$(cache_path)" ]
}
@test "CLAUDE_CONFIG_DIR is where credentials, cache and baseline live" {
    refresh "$NOW"
    [ -e "$CFG/cache/statusline/spend-usage" ] && [ -e "$CFG/cache/statusline/spend-usage.daystart" ]
    [ ! -e "$HOME/.claude/cache/statusline/spend-usage.tmp" ]
}
@test "holidays observed across New Year ride in December's cache: Christmas and New Year 2028 both land on Fridays" {
    creds "2027-12-20 12:00:00" 3600; refresh "2027-12-20 12:00:00" CLAUDE_SPEND_CALENDAR="$SHIPPED"
    run cache_contents; assert_has "2027-12-20 " " 1111100 24 31"
}
@test "a garbled baseline is re-pinned rather than trusted" {
    printf '2026-09-05 -5\n' > "$DAYSTART"; refresh "$NOW"
    assert_equal "$(cat "$DAYSTART")" "2026-09-05 120"; run cache_contents; assert_has " 0 120 400 "
}
@test "the amount's exponent sets the minor unit: exponent 0 and 3, and absent means 2" {
    FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":12000,"exponent":0},"limit":{"amount_minor":40000,"exponent":0}}}' refresh "$NOW"
    run cache_contents; assert_has " 12000 40000 "; rm -f "$(cache_path)"
    FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":12345,"exponent":3},"limit":{"amount_minor":40000,"exponent":3}}}' refresh "$NOW"
    run cache_contents; assert_has " 12.345 40 "; rm -f "$(cache_path)"
    FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":12000},"limit":{"amount_minor":40000}}}' refresh "$NOW"
    run cache_contents; assert_has " 120 400 "
}
# A response recorded from a Team organization with spend billing on
# 2026-09-05 (tests/fixtures/usage-response.json): $113.88 used of $400.
@test "the recorded real response: month 113.88, limit 400, rendered as 28%" {
    FAKE_CURL_BODY="$(cat "$TESTS_DIR/fixtures/usage-response.json")" refresh "$NOW"
    run cache_contents; assert_has " 113.88 400 "
    render "$NOW"; assert_has "month:" " 28% " '$114/$400'
}
@test "spend disabled in the response: no cache, an existing one is dropped, hold one interval" {
    setup_stamp; printf '2026-09-05 1 3.25 120 400 1111100 7\n' > "$(cache_path)"
    FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":0,"exponent":2},"limit":{"amount_minor":40000,"exponent":2},"enabled":false}}' refresh "$NOW"
    [ ! -e "$(cache_path)" ]; assert_near "$(cat "$HOLD")" "$(( STAMP + 60 ))"
    render "$NOW"; assert_lacks "month:" "day:" "off:"
}
