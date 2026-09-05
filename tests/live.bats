#!/usr/bin/env bats
# The drift probe: the real endpoint with the real credentials, run by hand
# (LIVE=1 bats tests/live.bats), never in CI. It says whether the response
# still has the shape the script depends on, and whether a real refresh
# through the script yields a cache line. Nothing is written outside the
# test's tmpdir; the credentials file is copied there, not touched.
load helpers
REAL_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
setup() {
    [ -n "${LIVE:-}" ] || skip "set LIVE=1 to probe the real endpoint"
    [ -r "$REAL_CFG/.credentials.json" ] || skip "no credentials at $REAL_CFG/.credentials.json"
    fresh_config; cp "$REAL_CFG/.credentials.json" "$CFG/"
    RESP="$BATS_TEST_TMPDIR/response.json"
}
fetch_live() {
    printf '%s\n' 'url = "https://api.anthropic.com/api/oauth/usage"' \
        "header = \"Authorization: Bearer $(jq -r '.claudeAiOauth.accessToken' "$CFG/.credentials.json")\"" \
        'header = "anthropic-beta: oauth-2025-04-20"' | curl -s -m 10 -w '\n%{http_code}' -K - > "$RESP"
}
@test "live: HTTP 200 and the fields the script reads are still there, with the recorded types" {
    fetch_live; run tail -1 "$RESP"; assert_equal "$output" 200
    sed -i '$d' "$RESP"
    local path
    for path in .spend.used.amount_minor .spend.used.exponent .spend.limit.amount_minor .spend.limit.exponent .spend.cap.credits.amount_minor .spend.enabled; do
        run jq -r "$path | type" "$RESP"
        assert_equal "$output" "$(jq -r "$path | type" "$TESTS_DIR/fixtures/usage-response.json")" || { echo "at $path"; false; }
    done
}
@test "live: a real refresh through the script writes a cache line with numbers" {
    export PATH="${PATH#$TESTS_DIR/bin:}"   # the real curl
    unset FAKE_CURL_BODY FAKE_CURL_LOG
    run _render "$INPUT_DEFAULT" "$(date '+%F %T')"; wait_refresh
    read -r _ _ day month limit rest < "$(cache_path)"
    is_number() { case "$1" in ''|*[!0-9.]*) return 1 ;; esac; }
    is_number "$day" && is_number "$month" && is_number "$limit" || { echo "cache: $(cache_contents)"; false; }
    [ ! -e "$CFG/cache/statusline/budget-usage.hold" ] || { echo "hold written: the fetch failed"; false; }
}
