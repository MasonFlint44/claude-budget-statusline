# Shared setup for the Bats suite. Loaded by every .bats file via `load helpers`.
#
# Every command under test runs on a pinned clock through libfaketime, so the
# goldens and the day/month arithmetic never depend on when the suite runs.

bats_require_minimum_version 1.5.0
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SL="$TESTS_DIR/../statusline/spend-statusline.sh"
SHIPPED="$TESTS_DIR/../statusline/config/calendar.conf"
CAL="$TESTS_DIR/calendars"
EXP="$TESTS_DIR/expected"
NOW="2026-09-05 12:00:00"      # a Saturday; Labor Day is Mon 09-07
export TZ=America/Chicago
export LC_ALL=C.UTF-8              # multibyte-aware ${#var} and regexes for the bar checks

# --- faketime ---
_find_faketime() {
    local c
    [ -n "${FAKETIME_LIB:-}" ] && { printf '%s' "$FAKETIME_LIB"; return; }
    for c in /usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1 /usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1 \
             /usr/lib/faketime/libfaketime.so.1 /usr/local/lib/faketime/libfaketime.so.1 /usr/lib64/faketime/libfaketime.so.1; do
        [ -r "$c" ] && { printf '%s' "$c"; return; }
    done
}
FAKETIME_LIB=$(_find_faketime)
[ -n "$FAKETIME_LIB" ] || { echo "libfaketime not found (apt install libfaketime, or set FAKETIME_LIB)" >&2; exit 2; }

# at "YYYY-MM-DD HH:MM:SS" cmd...   run cmd at that instant (interpreted in $TZ).
# The offset form is deliberate: an absolute FAKETIME string is re-parsed by
# every child process in ITS time zone, so a script that sets TZ for one date
# call would see a different instant. A signed-seconds offset is the same
# instant in every zone.
at() {
    local t="$1" off; shift
    off=$(( $(date -d "$t" +%s) - $(date +%s) ))
    LD_PRELOAD="$FAKETIME_LIB" FAKETIME="$(printf '%+ds' "$off")" FAKETIME_DONT_FAKE_MONOTONIC=1 FAKETIME_NO_CACHE=1 "$@"
}
epoch_at() { at "$1" date +%s; }

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# --- assertions (self-contained; no bats-assert dependency) ---
# Each prints the offending text so a failure reads on its own.
assert_has()   { local s; for s in "$@"; do case "$output" in *"$s"*) ;; *) echo "expected to find: $s"; echo "in: $output"; return 1 ;; esac; done; }
assert_lacks() { local s; for s in "$@"; do case "$output" in *"$s"*) echo "expected NOT to find: $s"; echo "in: $output"; return 1 ;; esac; done; }
assert_status() { [ "$status" = "$1" ] || { echo "exit status $status, expected $1"; echo "output: $output"; return 1; }; }
assert_equal()  { [ "$1" = "$2" ] || { echo "got:      $1"; echo "expected: $2"; return 1; }; }

# --- golden listings ---
# golden NAME CONF [YEAR] [VAR=value ...]
#   CONF = a fixture name in tests/calendars/, "shipped", "off", or an absolute path.
#   Runs `--calendar YEAR` at ${AT:-$NOW}, compares stdout then stderr with
#   tests/expected/NAME.txt. UPDATE=1 rewrites the golden instead.
golden() {
    local name="$1" conf="$2" year="${3:-}" path actual
    shift 2; [ $# -gt 0 ] && shift
    case "$conf" in shipped) path="$SHIPPED" ;; off|/*) path="$conf" ;; *) path="$CAL/$conf" ;; esac
    run --separate-stderr at "${AT:-$NOW}" env CLAUDE_SPEND_CALENDAR="$path" "$@" bash "$SL" --calendar $year
    actual=$(printf '%s\n--- stderr\n%s\n' "$output" "$stderr" \
        | sed "s#$TESTS_DIR/calendars/#calendars/#; s#$SHIPPED#statusline/config/calendar.conf#")
    if [ -n "${UPDATE:-}" ]; then printf '%s\n' "$actual" > "$EXP/$name.txt"; return 0; fi
    [ -r "$EXP/$name.txt" ] || { echo "no golden $EXP/$name.txt (run with UPDATE=1)"; return 1; }
    diff -u "$EXP/$name.txt" <(printf '%s\n' "$actual") || return 1
}

# --- rendering ---
# A private config dir per test, with the cache directory ready.
CFG=""
fresh_config() {
    CFG="$BATS_TEST_TMPDIR/cfg"
    rm -rf "$CFG"; mkdir -p "$CFG/cache/statusline"
    export CLAUDE_CONFIG_DIR="$CFG"
    # The render helpers hide the repo row through this display file, so the
    # spend-line tests see one row; display_file replaces it for a test.
    printf 'hide repo\n' > "$CFG/display-norepo.conf"
    DISPLAY_OVERRIDE=""
}
# display_file LINE...: a display file in the fresh config with those lines,
# used by the next renders instead of the repo-hiding default (so the repo
# row shows unless the lines hide it).
DISPLAY_OVERRIDE=""
display_file() {
    printf '%s\n' "$@" > "$CFG/display.conf"
    DISPLAY_OVERRIDE="$CFG/display.conf"
}
cache_path() { printf '%s/cache/statusline/spend-usage' "$CFG"; }
# cache_line "TIME" "<today$> <month$> <limit$> <mask> <holiday doms...>" [VAR=value ...]
#   Writes a cache line dated on the spend clock at TIME with a fresh stamp,
#   so the render uses it and does not trigger a refresh.
cache_line() {
    local t="$1" rest="$2" today stamp; shift 2
    today=$(at "$t" env "$@" bash -c 'd=${CLAUDE_SPEND_TZ:-}; if [ -n "$d" ]; then TZ=$d date +%F; else date +%F; fi')
    stamp=$(epoch_at "$t")
    printf '%s %s %s\n' "$today" "$stamp" "$rest" > "$(cache_path)"
}
INPUT_DEFAULT='{"model":{"display_name":"Opus"},"context_window":{"used_percentage":12},"cost":{"total_cost_usd":1.5},"workspace":{"current_dir":"/tmp"}}'
# render "TIME" [VAR=value ...]   -> $output = the statusline, ANSI stripped; $lines[] per row.
#   INPUT overrides the JSON; COLUMNS defaults to 120; the display file is the
#   fresh config's repo-hiding one unless display_file wrote another.
_render_raw() {
    local input="$1" t="$2"; shift 2
    printf '%s' "$input" | at "$t" env CLAUDE_CONFIG_DIR="$CFG" COLUMNS="${COLUMNS_OVERRIDE:-120}" CLAUDE_SPEND_DISPLAY="${DISPLAY_OVERRIDE:-$CFG/display-norepo.conf}" "$@" bash "$SL"
}
_render() { _render_raw "$@" | strip_ansi; }
render() { local t="$1"; shift; run _render "${INPUT:-$INPUT_DEFAULT}" "$t" "$@"; }
# render_raw: the same, escapes kept, for the colour checks.
render_raw() { local t="$1"; shift; run _render_raw "${INPUT:-$INPUT_DEFAULT}" "$t" "$@"; }
# first_line -> the first row only, for assertions on the spend line.
first_line() { printf '%s' "${lines[0]:-}"; }

# Wait for the detached refresh to finish: the lock dir goes away when it does.
wait_refresh() {
    local i
    for i in $(seq 1 100); do [ -d "$CFG/cache/statusline/spend-usage.lock" ] || return 0; sleep 0.05; done
    echo "refresh did not finish"; return 1
}

# --- the fetch path, with the fake curl in tests/bin ---
CREDS=""; DAYSTART=""; HOLD=""
fetch_setup() {
    fresh_config
    export PATH="$TESTS_DIR/bin:$PATH"
    export FAKE_CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
    CREDS="$CFG/.credentials.json"
    DAYSTART="$CFG/cache/statusline/spend-usage.daystart"
    HOLD="$CFG/cache/statusline/spend-usage.hold"
    creds "$NOW" 3600      # a token valid for an hour past NOW
    export FAKE_CURL_BODY='{"spend":{"used":{"amount_minor":12000,"currency":"USD","exponent":2},"limit":{"amount_minor":40000,"currency":"USD","exponent":2}}}'
    unset FAKE_CURL_CODE FAKE_CURL_EXIT FAKE_CURL_SLEEP
}
# creds "TIME" SECONDS-UNTIL-EXPIRY   (write a credentials file; "none" = no expiresAt)
creds() {
    if [ "$2" = none ]; then printf '{"claudeAiOauth":{"accessToken":"tok-123"}}\n' > "$CREDS"
    else printf '{"claudeAiOauth":{"accessToken":"tok-123","expiresAt":%s}}\n' "$(( ($(epoch_at "$1") + $2) * 1000 ))" > "$CREDS"; fi
}
# refresh "TIME" [VAR=value ...]: render once with no usable cache (which
# triggers the detached refresh), wait for it, leave $output = the render.
refresh() { local t="$1"; shift; render "$t" "$@"; wait_refresh; }
cache_contents() { cat "$(cache_path)" 2>/dev/null; }
curl_calls() { grep -c -- '^--- argv:' "$FAKE_CURL_LOG" 2>/dev/null || echo 0; }

# assert_near ACTUAL EXPECTED [TOLERANCE]: integers within EXPECTED-1 ..
# EXPECTED+TOLERANCE (default 2). Fake time runs at real speed, so a stamp the
# script takes can trail one the test took by a second or two; and because
# each at() computes its offset in whole seconds, it can also land one second
# earlier.
assert_near() {
    local a="$1" e="$2" t="${3:-2}"
    [ "$a" -ge $(( e - 1 )) ] 2>/dev/null && [ "$a" -le $(( e + t )) ] || { echo "got $a, expected $e (-1/+$t)"; return 1; }
}
