#!/usr/bin/env bats
# --doctor and --help: every branch the refresh can take, explained on
# stdout, with exit 1 whenever the bars would stay hidden.
load helpers
setup() { fetch_setup; }
doctor() { run at "$NOW" env CLAUDE_CONFIG_DIR="$CFG" "$@" bash "$SL" --doctor; }

@test "--help exits 0 and names every flag and knob" {
    run bash "$SL" --help; assert_status 0
    assert_has "--calendar" "--display" "--doctor" "--help" "CLAUDE_BUDGET_MONTHLY_LIMIT" "CLAUDE_BUDGET_TZ" "CLAUDE_BUDGET_REFRESH" "CLAUDE_BUDGET_CALENDAR" "CLAUDE_BUDGET_DISPLAY" "CLAUDE_CONFIG_DIR"
    run bash "$SL" -h; assert_status 0
}
@test "the script's VERSION matches plugin.json" {
    run bash "$SL" --help; assert_has "budget-statusline $(jq -r .version "$TESTS_DIR/../.claude-plugin/plugin.json")"
}
@test "--doctor with an argument is rejected" { run bash "$SL" --doctor now; assert_status 2; assert_has "usage:"; }
@test "--doctor reads nothing from stdin" {
    run timeout 10 bash -c "cd '$TESTS_DIR' && . helpers.bash && at '$NOW' env CLAUDE_CONFIG_DIR='$CFG' bash '$SL' --doctor" <&-; assert_status 0
}
@test "healthy: every step reported, cache written, exit 0" {
    doctor; assert_status 0
    assert_has "version:" "config dir:   $CFG" "today 2026-09-05" "workdays mon tue wed thu fri, 11 holidays in 2026" \
               "September 2026, 17 workday(s) left" "OAuth token present, expires in 1h 0m" \
               "HTTP 200: month to date \$120, limit \$400" "limit:        \$400 from the response" \
               "today \$0, month \$120, limit \$400" "bars:         will show"
    line=$(cut -d' ' -f3- "$(cache_path)"); assert_equal "${line% }" "0 120 400 1111100 7"; [ ! -e "$HOLD" ]
}
@test "the calendar line reports unparsed lines and the off state" {
    doctor CLAUDE_BUDGET_CALENDAR="$TESTS_DIR/calendars/bad-lines.conf"; assert_status 0; assert_has "line(s) not parsed (see --calendar)"
    doctor CLAUDE_BUDGET_CALENDAR=off; assert_has "calendar:     off (CLAUDE_BUDGET_CALENDAR=off)" "18 workday(s) left"
    doctor CLAUDE_BUDGET_CALENDAR=/nope; assert_has "no file at /nope"
}
@test "no credentials file: says so, exit 1, nothing fetched" {
    rm "$CREDS"; doctor; assert_status 1; assert_has "credentials:  no credentials file at $CREDS" "log in with claude" "bars:         hidden"
    assert_equal "$(curl_calls)" 0
}
@test "credentials without a token" {
    printf '{"primaryApiKey":"sk-ant"}\n' > "$CREDS"; doctor; assert_status 1; assert_has "no OAuth token in $CREDS"
}
@test "expired token" { creds "$NOW" -5; doctor; assert_status 1; assert_has "the OAuth token expired"; assert_equal "$(curl_calls)" 0; }
@test "curl failure" { FAKE_CURL_EXIT=7 doctor; assert_status 1; assert_has "usage fetch:  curl failed"; }
@test "HTTP 401, 429 and 500 each get their own line" {
    FAKE_CURL_CODE=401 doctor; assert_status 1; assert_has "HTTP 401: the token was rejected"
    FAKE_CURL_CODE=429 doctor; assert_status 1; assert_has "HTTP 429: rate limited"
    FAKE_CURL_CODE=500 FAKE_CURL_BODY='{"error":"boom"}' doctor; assert_status 1; assert_has 'HTTP 500: {"error":"boom"}'
}
@test "spend billing off" {
    FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":0},"enabled":false}}' doctor; assert_status 1; assert_has "spend.enabled is false"
}
@test "a response with no spend figure" {
    FAKE_CURL_BODY='{"five_hour":{"utilization":3}}' doctor; assert_status 1; assert_has "no spend figure in the response" '{"five_hour"'
}
@test "no limit anywhere: exit 1 and the knob named; the knob fixes it" {
    FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":12000,"exponent":2}}}' doctor; assert_status 1; assert_has "limit:        none" "CLAUDE_BUDGET_MONTHLY_LIMIT"
    FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":12000,"exponent":2}}}' doctor CLAUDE_BUDGET_MONTHLY_LIMIT=300; assert_status 0
    assert_has "limit:        \$300 from CLAUDE_BUDGET_MONTHLY_LIMIT" "month \$120, limit \$300"
}
@test "a Keychain fallback is never tried on Linux" {
    rm "$CREDS"; mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\necho called >> "%s/security.log"; echo "{}"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/security"; chmod +x "$BATS_TEST_TMPDIR/bin/security"
    doctor PATH="$BATS_TEST_TMPDIR/bin:$PATH"; assert_status 1; [ ! -e "$BATS_TEST_TMPDIR/security.log" ]
}
@test "on macOS with no file, the Keychain item is read (OSTYPE and a fake security)" {
    rm "$CREDS"; mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/security" <<'SH'
#!/bin/sh
echo "$*" >> "${FAKE_SEC_LOG:?}"
[ "$1" = find-generic-password ] || exit 44
printf '{"claudeAiOauth":{"accessToken":"tok-kc","expiresAt":%s}}\n' "$FAKE_SEC_EXP"
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/security"
    doctor PATH="$BATS_TEST_TMPDIR/bin:$PATH" OSTYPE=darwin24 FAKE_SEC_LOG="$BATS_TEST_TMPDIR/sec.log" FAKE_SEC_EXP="$(( ($(epoch_at "$NOW") + 3600) * 1000 ))"
    assert_status 0; assert_has "credentials:  the macOS Keychain (Claude Code-credentials): OAuth token present"
    assert_equal "$(cat "$BATS_TEST_TMPDIR/sec.log")" 'find-generic-password -s Claude Code-credentials -w'
    run cat "$FAKE_CURL_LOG"; assert_has 'Bearer tok-kc'
    # and the missing item is reported
    printf '#!/bin/sh\nexit 44\n' > "$BATS_TEST_TMPDIR/bin/security"
    doctor PATH="$BATS_TEST_TMPDIR/bin:$PATH" OSTYPE=darwin24; assert_status 1; assert_has "no credentials file and no Keychain item"
}
@test "missing jq is the first thing reported, before any credentials guess" {
    mkdir -p "$BATS_TEST_TMPDIR/nojq"; for t in bash curl awk cat env sed grep sort mkdir rm mv cut tr timeout git faketime readlink apt-get; do p=$(command -v $t) && ln -s "$p" "$BATS_TEST_TMPDIR/nojq/$t"; done
    ln -s "$TESTS_DIR/bin/curl" "$BATS_TEST_TMPDIR/nojq/curl" 2>/dev/null || true
    doctor PATH="$BATS_TEST_TMPDIR/nojq"; assert_status 1; assert_has "tools:        missing: jq" "bars:         hidden"; assert_lacks "credentials:"
    # the hint follows the platform: this box has apt-get; macOS and Git Bash by OSTYPE
    assert_has "Install: sudo apt install jq"
    doctor PATH="$BATS_TEST_TMPDIR/nojq" OSTYPE=darwin24; assert_has "Install: brew install jq"
    doctor PATH="$BATS_TEST_TMPDIR/nojq" OSTYPE=msys; assert_has "Install: winget install jqlang.jq (in Git Bash, or PowerShell)"
    # no package manager found at all: a generic hint
    rm "$BATS_TEST_TMPDIR/nojq/apt-get"
    doctor PATH="$BATS_TEST_TMPDIR/nojq" OSTYPE=linux-gnu; assert_has "Install: install jq with your package manager"
    # two tools missing: one command names both
    rm "$BATS_TEST_TMPDIR/nojq/curl"; ln -s "$(command -v apt-get)" "$BATS_TEST_TMPDIR/nojq/apt-get"
    doctor PATH="$BATS_TEST_TMPDIR/nojq"; assert_has "missing: jq curl. Install: sudo apt install jq curl"
}
@test "the tools line names bash and the optional git" {
    doctor; assert_has "tools:        bash $BASH_VERSION, jq, curl, awk, readlink"
}
@test "an unwritable cache directory: cache: could not write, exit 1, even with an old line in place" {
    [ "$(id -u)" = 0 ] && skip "root can write anywhere"
    printf '2026-09-05 1 0 100 400 1111100 7\n' > "$(cache_path)"; chmod 555 "$CFG/cache/statusline"
    doctor; chmod 755 "$CFG/cache/statusline"; assert_status 1
    assert_has "HTTP 200" "cache:        could not write" "bars:         hidden"; assert_lacks "refreshed just now"
}
