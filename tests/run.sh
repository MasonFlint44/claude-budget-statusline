#!/usr/bin/env bash
# Test suite for statusline/budget-statusline.sh. Pure bash; needs libfaketime
# (apt: libfaketime) so every run sees the same clock, plus the script's own
# dependencies (jq, awk, GNU date).
#
#   tests/run.sh             run everything
#   UPDATE=1 tests/run.sh    rewrite the golden files from the current output
#   tests/run.sh -v          also print each passing check
#
# Three kinds of check:
#   golden   --calendar output for a fixture in tests/calendars/, compared
#            with tests/expected/<name>.txt (stdout, then stderr).
#   render   the statusline's first line for a hand-written cache line,
#            ANSI stripped, checked for substrings.
#   cli      exit codes and messages for the flag handling.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SL="$HERE/../statusline/budget-statusline.sh"
SHIPPED="$HERE/../statusline/config/calendar.conf"
CAL="$HERE/calendars"
EXP="$HERE/expected"
VERBOSE=""; [ "${1:-}" = -v ] && VERBOSE=1

# --- faketime: the whole suite runs on a pinned clock ---
LIB="${FAKETIME_LIB:-}"
for c in /usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1 /usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1 \
         /usr/lib/faketime/libfaketime.so.1 /usr/local/lib/faketime/libfaketime.so.1 /usr/lib64/faketime/libfaketime.so.1; do
    [ -n "$LIB" ] && break
    [ -r "$c" ] && LIB="$c"
done
[ -n "$LIB" ] || { echo "tests: libfaketime not found (apt install libfaketime, or set FAKETIME_LIB)" >&2; exit 2; }
NOW="2026-09-05 12:00:00"      # a Saturday; Labor Day is Mon 09-07
export TZ=America/Chicago
# Run $2.. at fake time $1 ("YYYY-MM-DD HH:MM:SS", in $TZ). The offset form:
# an absolute FAKETIME string is re-parsed by every child process in ITS time
# zone, so a script that sets TZ for one date call would see a different
# instant. A signed-seconds offset is the same instant in every zone.
at() {
    local t="$1" off; shift
    off=$(( $(date -d "$t" +%s) - $(date +%s) ))
    LD_PRELOAD="$LIB" FAKETIME="$(printf '%+ds' "$off")" FAKETIME_DONT_FAKE_MONOTONIC=1 FAKETIME_NO_CACHE=1 "$@"
}
at "$NOW" date +%F | grep -q '^2026-09-05$' || { echo "tests: faketime is not taking effect ($LIB)" >&2; exit 2; }

pass=0; fail=0
ok()  { pass=$((pass + 1)); [ -n "$VERBOSE" ] && echo "ok   $1"; return 0; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; return 0; }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

# --- golden: --calendar output vs tests/expected/<name>.txt ---
# golden NAME CONF [YEAR] [VAR=value ...]   CONF = fixture name or "shipped"
# Runs at $NOW unless AT="YYYY-MM-DD HH:MM:SS" is set for the call.
golden() {
    local name="$1" conf="$2" year="${3:-}" path out err actual
    shift 2; [ $# -gt 0 ] && shift
    case "$conf" in shipped) path="$SHIPPED" ;; off|/*) path="$conf" ;; *) path="$CAL/$conf" ;; esac
    out=$(at "${AT:-$NOW}" env CLAUDE_BUDGET_CALENDAR="$path" "$@" bash "$SL" --calendar $year 2>"$HERE/.stderr"); err=$(cat "$HERE/.stderr"); rm -f "$HERE/.stderr"
    # The path line names an absolute path; normalise it.
    actual=$(printf '%s\n--- stderr\n%s\n' "$out" "$err" | sed "s#$HERE/calendars/#calendars/#; s#$SHIPPED#statusline/config/calendar.conf#")
    if [ -n "${UPDATE:-}" ]; then printf '%s\n' "$actual" > "$EXP/$name.txt"; ok "$name (updated)"; return; fi
    if [ -r "$EXP/$name.txt" ] && diff=$(diff -u "$EXP/$name.txt" <(printf '%s\n' "$actual")); then ok "$name"
    else bad "$name" "${diff:-no golden file $EXP/$name.txt (run with UPDATE=1)}"; fi
}

# --- render: first statusline line for a cache line ---
# render NAME "TIME" "CACHE-LINE-AFTER-DATE-AND-STAMP" [VAR=value ...]; then
# has NAME substring...   /  lacks NAME substring...
RDIR="$HERE/.render"
LINE=""
render() {
    local name="$1" t="$2" rest="$3" today stamp
    shift 3
    rm -rf "$RDIR"; mkdir -p "$RDIR/cache/statusline"
    today=$(at "$t" env "$@" bash -c 'd=${CLAUDE_BUDGET_TZ:-}; if [ -n "$d" ]; then TZ=$d date +%F; else date +%F; fi')
    stamp=$(at "$t" date +%s)
    printf '%s %s %s\n' "$today" "$stamp" "$rest" > "$RDIR/cache/statusline/budget-usage"
    LINE=$(printf '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":12},"cost":{"total_cost_usd":1.5},"workspace":{"current_dir":"%s"}}' "$HERE" \
        | at "$t" env CLAUDE_CONFIG_DIR="$RDIR" COLUMNS=120 CLAUDE_BUDGET_REPO_LINE=off "$@" bash "$SL" | strip | head -1)
    [ -n "$VERBOSE" ] && echo "     $name: $LINE"
    return 0
}
has()   { local name="$1" s; shift; for s in "$@"; do case "$LINE" in *"$s"*) ok "$name has '$s'" ;; *) bad "$name has '$s'" "line: $LINE" ;; esac; done; }
lacks() { local name="$1" s; shift; for s in "$@"; do case "$LINE" in *"$s"*) bad "$name lacks '$s'" "line: $LINE" ;; *) ok "$name lacks '$s'" ;; esac; done; }

# --- cli: exit code + message ---
# cli NAME EXPECTED-RC "STDERR-SUBSTRING" args...
cli() {
    local name="$1" want="$2" msg="$3" rc err; shift 3
    err=$(at "$NOW" bash "$SL" "$@" </dev/null 2>&1 >/dev/null); rc=$?
    if [ "$rc" = "$want" ] && case "$err" in *"$msg"*) true ;; *) false ;; esac; then ok "$name"
    else bad "$name" "rc=$rc (want $want) stderr: $err"; fi
}

# ======================= golden listings =======================
golden shipped-2026 shipped 2026
golden shipped-2027 shipped 2027       # Juneteenth Sat, Jul 4 Sun, Christmas Sat, Jan 1 2028 Sat
golden shipped-2022 shipped 2022       # Jan 1 Sat -> observed Fri 2021-12-31; Dec 25 Sun
golden shipped-current shipped         # no year: this year, plus the month line
golden uk-2027 uk.conf 2027            # Christmas Sat + Boxing Day Sun chain to Mon/Tue with "next"
golden japan-2025 japan.conf 2025      # sat=none loses Constitution Day; Greenery Day skips taken Monday
golden europe-2027 europe.conf 2027    # observe none: weekend holidays are lost
golden sun-thu-2026 sun-thu.conf 2026  # Fri rule -> Thu, Sat holiday -> Sun, once range across the weekend
golden mon-thu-2026 mon-thu.conf 2026  # three-day weekend: nearest tie -> forward; old two-key overrides
golden sparse-2027 sparse.conf 2027    # workdays mon: chain, then no free workday within two weeks
golden pto-chain-2027 pto-chain.conf 2027   # holiday observed onto a PTO day stays there; mixed-case modes
golden pto-chain-2026 pto-chain.conf 2026   # tabs inside names
golden all-2026 all.conf 2026          # seven-day week: nothing is ever shifted
golden empty-2026 empty.conf 2026      # no lines: defaults
golden dupes-2026 dupes.conf 2026      # last workdays/observe wins; duplicate dates dropped
golden nth-last-2026 nth-last.conf 2026
golden nth-last-2027 nth-last.conf 2027   # no fifth Friday in May 2027
golden bad-lines-2026 bad-lines.conf 2026 # every warning path, plus a cross-year once range
golden cross-year-2025 cross-year.conf 2025
golden cross-year-2026 cross-year.conf 2026
golden cross-year-2027 cross-year.conf 2027
golden glob-2026 glob.conf 2026        # "*" in a workdays line must not expand against the cwd
golden dst-chicago dst-ranges.conf 2026
golden dst-auckland dst-ranges.conf 2026 TZ=Pacific/Auckland
golden dst-london dst-ranges.conf 2026 TZ=Europe/London
golden off off 2026                    # CLAUDE_BUDGET_CALENDAR=off
golden missing /nonexistent/calendar.conf 2026
# Fri 09-04 20:00 Chicago is Sat 09-05 13:00 in Auckland: 18 workdays remain locally, 17 there.
AT="2026-09-04 20:00:00" golden tz-chicago shipped ""
AT="2026-09-04 20:00:00" golden tz-auckland shipped "" CLAUDE_BUDGET_TZ=Pacific/Auckland

# ======================= cli =======================
cli unknown-flag 2 "usage:" --holidays 2027
cli bad-year 2 "usage:" --calendar 20x
cli extra-arg 2 "usage:" --calendar 2026 extra
cli stray-arg 2 "usage:" render-me

# ======================= render =======================
# Cache line after "<date> <stamp>": <today$> <month$> <limit$> <mask> <holiday doms...>
# At NOW (Sat 09-05) with mon-fri, 17 workdays remain after today (Labor Day off):
# allowance = (400 - (120 - 3.25)) / 17 = 16.66 -> "$17", 3.25/16.66 = 19%.
render sat-monfri "$NOW" "3.25 120 400 1111100 7"
has   sat-monfri "off:" " 19% " '$3.25/$17' "month:" " 30% " '$120/$400'
lacks sat-monfri "day:"
# Seven-day week: 26 days left incl. today -> 283.25/26 = 10.9 -> "$11", 28%.
render sat-all "$NOW" "3.25 120 400 1111111 7"
has   sat-all "day:" " 28% " '$3.25/$11'
lacks sat-all "off:"
# Today listed as a holiday (dom 5) on a seven-day week: off, 25 days ahead -> $11.
render holiday-today "$NOW" "3.25 120 400 1111111 5"
has   holiday-today "off:" '$3.25/$11'
# A workday: Mon 09-14, 13 workdays left incl. today -> (400-100)/13 = 23.08 -> "$23"; 20/23.08 = 86%.
render weekday "2026-09-14 09:30:00" "20 120 400 1111100 7"
has   weekday "day:" " 86% " '$20/$23'
# Budget clock ahead of local: Fri 09-04 20:00 CDT is Sat 09-05 13:00 in Auckland -> off.
render tz-local "2026-09-04 20:00:00" "1 100 400 1111100 7"
has   tz-local "day:"
render tz-auckland "2026-09-04 20:00:00" "1 100 400 1111100 7" CLAUDE_BUDGET_TZ=Pacific/Auckland
has   tz-auckland "off:"
# Month past the limit: bar pegs, overage shown, day allowance gone (no denominator).
render over "$NOW" "5 450 400 1111100 7"
has   over "month:" "112%" '$450/$400' '+$50' 'off:' '999%' '$5.00 '
lacks over '$5.00/'
# Old cache format (no mask): treated as no cache, bars hidden.
render old-cache "$NOW" "3.25 120 400 7"
lacks old-cache "day:" "off:" "month:"
has   old-cache "ctx:"
# No limit known: bars hidden.
render no-limit "$NOW" "3.25 120 0 1111100 7"
lacks no-limit "day:" "month:"
# Yesterday's cache line: hidden (the date check), not misreported.
YDAY=$(at "$NOW" date -d yesterday +%F); STAMP=$(at "$NOW" date +%s)
rm -rf "$RDIR"; mkdir -p "$RDIR/cache/statusline"; printf '%s %s 3.25 120 400 1111100 7\n' "$YDAY" "$STAMP" > "$RDIR/cache/statusline/budget-usage"
LINE=$(echo '{}' | at "$NOW" env CLAUDE_CONFIG_DIR="$RDIR" COLUMNS=120 CLAUDE_BUDGET_REPO_LINE=off bash "$SL" | strip | head -1)
lacks stale-cache "day:" "off:" "month:"
# Garbage on stdin still renders (an empty line, exit 0).
if echo 'not json' | at "$NOW" env CLAUDE_CONFIG_DIR="$RDIR" bash "$SL" >/dev/null 2>&1; then ok "garbage-stdin exits 0"; else bad "garbage-stdin exits 0"; fi
rm -rf "$RDIR"

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
