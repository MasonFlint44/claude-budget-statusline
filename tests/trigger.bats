#!/usr/bin/env bats
# When a render kicks off a background refresh: cache age against the
# interval, the hold file, the lock, and the CLAUDE_SPEND_REFRESH knob.
load helpers
setup() { fetch_setup; STAMP=$(epoch_at "$NOW"); }
# aged N: a valid cache line whose stamp is N seconds before NOW (negative = future).
aged() { printf '2026-09-05 %s 3.25 120 400 1111100 7\n' "$(( STAMP - $1 ))" > "$(cache_path)"; }
# tick: render at NOW and give a refresh (if any) time to run.
tick() { render "$NOW" "$@"; wait_refresh; }

@test "a fresh cache does not refresh" { aged 0; tick; assert_equal "$(curl_calls)" 0; assert_has "month:"; }
# 58, not 59: the script's clock can tick one second past the test's stamp
# (libfaketime offsets are whole seconds), and 59 + 1 is the boundary.
@test "a cache 58 s old does not refresh" { aged 58; tick; assert_equal "$(curl_calls)" 0; }
@test "a cache 60 s old refreshes and is replaced" {
    aged 60; tick; assert_equal "$(curl_calls)" 1
    run cache_contents; assert_has "2026-09-05 " " 0 120 400 "; assert_lacks "3.25"
}
@test "the stale cache still renders while the refresh runs" { aged 600; tick; assert_has "month:" '$120/$400'; }
@test "a stamp from the future (clock skew) counts as stale" { aged -100; tick; assert_equal "$(curl_calls)" 1; }
@test "no cache at all refreshes" { tick; assert_equal "$(curl_calls)" 1; }
@test "a hold in the future suppresses the refresh" {
    printf '%s\n' "$(( STAMP + 30 ))" > "$HOLD"; aged 600; tick; assert_equal "$(curl_calls)" 0
}
@test "a hold that has passed does not" {
    printf '%s\n' "$(( STAMP - 1 ))" > "$HOLD"; aged 600; tick; assert_equal "$(curl_calls)" 1
}
@test "a garbled hold file is ignored" { printf 'soon\n' > "$HOLD"; aged 600; tick; assert_equal "$(curl_calls)" 1; }
@test "a live lock (stamped within five minutes) blocks a second refresher" {
    mkdir "$CFG/cache/statusline/spend-usage.lock"; printf '%s\n' "$(( STAMP - 299 ))" > "$CFG/cache/statusline/spend-usage.lock/stamp"
    aged 600; render "$NOW"; sleep 0.3; assert_equal "$(curl_calls)" 0
    rmdir "$CFG/cache/statusline/spend-usage.lock" 2>/dev/null || rm -rf "$CFG/cache/statusline/spend-usage.lock"
}
@test "a stale lock (older than five minutes) is cleared and the refresh runs" {
    mkdir "$CFG/cache/statusline/spend-usage.lock"; printf '%s\n' "$(( STAMP - 301 ))" > "$CFG/cache/statusline/spend-usage.lock/stamp"
    aged 600; tick; assert_equal "$(curl_calls)" 1; [ ! -d "$CFG/cache/statusline/spend-usage.lock" ]
}
@test "a lock without a stamp counts as stale" {
    mkdir "$CFG/cache/statusline/spend-usage.lock"; aged 600; tick; assert_equal "$(curl_calls)" 1
}
@test "two renders while one refresh is in flight make one request" {
    aged 600
    FAKE_CURL_SLEEP=0.5 render "$NOW"; render "$NOW"; render "$NOW"
    wait_refresh; assert_equal "$(curl_calls)" 1
}
@test "the lock is released after the refresh" { aged 600; tick; [ ! -d "$CFG/cache/statusline/spend-usage.lock" ]; }
@test "CLAUDE_SPEND_REFRESH=120: 117 s is fresh, 120 s is stale" {
    aged 117; tick CLAUDE_SPEND_REFRESH=120; assert_equal "$(curl_calls)" 0
    aged 120; tick CLAUDE_SPEND_REFRESH=120; assert_equal "$(curl_calls)" 1
}
@test "CLAUDE_SPEND_REFRESH below 10 clamps to 10" {
    aged 9;  tick CLAUDE_SPEND_REFRESH=5; assert_equal "$(curl_calls)" 0
    aged 10; tick CLAUDE_SPEND_REFRESH=5; assert_equal "$(curl_calls)" 1
}
@test "a non-integer CLAUDE_SPEND_REFRESH falls back to 60" {
    aged 57; tick CLAUDE_SPEND_REFRESH=soon; assert_equal "$(curl_calls)" 0   # 57: room for the fake clock's jitter, as above
    aged 60; tick CLAUDE_SPEND_REFRESH=soon; assert_equal "$(curl_calls)" 1
}
@test "the refresh never blocks the render" {
    aged 600; local t0 t1; t0=$(date +%s%N); FAKE_CURL_SLEEP=2 render "$NOW"; t1=$(date +%s%N)
    [ $(( (t1 - t0) / 1000000 )) -lt 1500 ] || { echo "render took $(( (t1 - t0) / 1000000 )) ms"; false; }
    wait_refresh
}

# --- damaged cache files: each is treated as no cache, so the render hides
#     the bars, exits 0, and triggers a refresh that rewrites the line ---
@test "an empty cache file" {
    : > "$(cache_path)"; tick; assert_status 0; assert_lacks "month:"; assert_equal "$(curl_calls)" 1
    read -r _ _ rest < "$(cache_path)"; [[ "$rest" == "0 120 400 1111100 7"* ]]
}
@test "a cache line cut off mid-write (date and stamp only)" {
    printf '2026-09-05 %s' "$STAMP" > "$(cache_path)"; tick; assert_status 0; assert_lacks "month:" "day:" "off:"; assert_equal "$(curl_calls)" 1
}
@test "a cache line missing its newline still parses" {
    printf '2026-09-05 %s 3.25 120 400 1111100 7' "$STAMP" > "$(cache_path)"; tick; assert_has "month:"; assert_equal "$(curl_calls)" 0
}
@test "binary junk in the cache" {
    head -c 200 /dev/urandom > "$(cache_path)"; tick; assert_status 0; assert_lacks "month:"; assert_equal "$(curl_calls)" 1
}
@test "a cache file that is a directory" {
    rm -f "$(cache_path)"; mkdir "$(cache_path)"; tick; assert_status 0; assert_lacks "month:"
    run cat "$FAKE_CURL_LOG"; assert_status 0   # the refresh ran, and could not write; no crash either way
    rmdir "$(cache_path)" 2>/dev/null || rm -rf "$(cache_path)"
}
@test "an unreadable baseline file does not stop the refresh" {
    printf '2026-09-05 100\n' > "$DAYSTART"; chmod 000 "$DAYSTART"; rm -f "$(cache_path)"; tick
    read -r _ _ rest < "$(cache_path)"; [[ "$rest" == "0 120 400 1111100 7"* ]]; chmod 644 "$DAYSTART"
}
