#!/usr/bin/env bash
# Claude Code statusline with a daily + monthly spend budget, read from the
# same usage endpoint the /usage page renders (real billed dollars; the monthly
# limit comes from the org). Plus model, effort, context, session cost, git.
#
# Ships as: this file + config/calendar.conf (see README.md for install and
# prerequisites). `budget-statusline.sh --calendar [YEAR]` prints the calendar.
#
#   day: today's spend vs today's allowance, where the allowance divides the
#        month's REMAINING budget (as of this morning) evenly over the
#        remaining workdays of the month, today included:
#            allowance = (limit - (monthly - daily)) / workdays_left
#        workdays = the days of the week you work, minus holidays, both
#        from config/calendar.conf (evaluated at refresh time, cached);
#        one-off closures or PTO go there too as "once" lines.
#        Subtracting daily from monthly freezes the
#        allowance at its start-of-day value -- otherwise today's own spend
#        would shrink its own denominator. On a non-workday the label
#        reads "off:" and workdays_left counts the workdays after today
#        (floored at 1), so that spend draws against the next workday's slice.
#   month: monthly spend vs the monthly limit. Past the limit the bar pegs,
#        the percent keeps counting, and a coral "+$N" shows the overage
#        (e.g. a month where the limit got raised on request).
#
# The monthly limit is CLAUDE_BUDGET_MONTHLY_LIMIT if set (your own target,
# even when the org sets a higher one), else the limit in the usage response.
# With neither, the budget bars stay hidden.
#
# Wire-up (~/.claude/settings.json):
#   "statusLine": { "type": "command", "command": "bash /path/to/budget-statusline.sh" }

# printf '%.0f' must parse "42.5" regardless of the user's locale. LC_ALL
# would override LC_NUMERIC, so fold it into the category-level settings.
if [ -n "${LC_ALL:-}" ]; then export LC_CTYPE="$LC_ALL" LC_TIME="$LC_ALL"; unset LC_ALL; fi
export LC_NUMERIC=C
SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")
# The budget clock: CLAUDE_BUDGET_TZ if set (any TZ name), else local time.
BUDGET_TZ="${CLAUDE_BUDGET_TZ:-}"
bdate() { if [ -n "$BUDGET_TZ" ]; then TZ="$BUDGET_TZ" date "$@"; else date "$@"; fi; }
# The calendar: CLAUDE_BUDGET_CALENDAR if set (a path, or off), else config/calendar.conf.
CALENDAR="${CLAUDE_BUDGET_CALENDAR:-$SCRIPT_DIR/config/calendar.conf}"
case "$CALENDAR" in off|none|0|false) CALENDAR="" ;; esac   # no file: workdays mon-fri, no holidays

# --- Calendar (config/calendar.conf) ---
# Which days of the week you work and which dates are holidays, so the daily
# allowance is spread over the days you actually work. One entry per line,
# "#" starts a comment, names run to the end of the line:
#   workdays DAYS           the days you work: a wrapping range (mon-fri,
#                           sun-thu), a list (mon,tue,wed,thu), a mix
#                           (mon-wed,fri) or "all". Default mon-fri. Last wins.
#   observe MODE [DOW=MODE ...]
#                           how a yearly holiday that falls on a non-workday
#                           is observed. MODE: nearest = the nearest workday,
#                           ties go forward (the default; US federal on a
#                           mon-fri week); next / prev = always that way;
#                           none = no substitute day. DOW=MODE overrides the
#                           mode for one day (Japan: "observe next sat=none").
#                           The substitute skips days that are already
#                           holidays, so Christmas and Boxing Day chain.
#                           Applies file-wide wherever the line sits.
#   fixed MM-DD      name   a yearly holiday on a fixed date
#   nth   N DOW MM   name   Nth weekday of a month (DOW = mon..sun, N = 1..5;
#                           a fifth that the month lacks is skipped)
#   last  DOW MM     name   last weekday of a month
#   once  YYYY-MM-DD[..YYYY-MM-DD] name
#                           a one-off date or inclusive range (PTO, closures).
#                           Literal: never shifted. One that lands on a day
#                           you don't work anyway simply has no effect.
# Yearly rules (fixed/nth/last) follow the observe policy; once lines don't.
# Lines that don't parse are skipped (reported by --calendar).

dow_num() {  # mon..sun -> 1..7 (matches date +%u); empty if unknown
    case "$1" in
        [Mm][Oo][Nn]) echo 1 ;; [Tt][Uu][Ee]) echo 2 ;; [Ww][Ee][Dd]) echo 3 ;;
        [Tt][Hh][Uu]) echo 4 ;; [Ff][Rr][Ii]) echo 5 ;; [Ss][Aa][Tt]) echo 6 ;;
        [Ss][Uu][Nn]) echo 7 ;; *) echo "" ;;
    esac
}
dow_abbr() {  # 1..7 -> Mon..Sun
    case "$1" in 1) echo Mon ;; 2) echo Tue ;; 3) echo Wed ;; 4) echo Thu ;; 5) echo Fri ;; 6) echo Sat ;; 7) echo Sun ;; esac
}
str_set() { printf '%s%s%s' "${1:0:$(($2 - 1))}" "$3" "${1:$2}"; }   # $1 with char $2 (1-based) replaced by $3
is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
is_mask() { case "$1" in [01][01][01][01][01][01][01]) return 0 ;; *) return 1 ;; esac; }
is_workday() { [ "${1:$(($2 - 1)):1}" = 1 ]; }   # $1 = mask, $2 = day-of-week 1..7

# The file's settings: wd_mask (7 chars indexed by date +%u, 1 = workday),
# obs_mode (nearest|next|prev|none) and obs_day (7 chars: ~ nearest, > next,
# < prev, x none, - inherit obs_mode). Defaults first, then the file's lines,
# last one wins. Bad tokens are reported on stderr when $2 is non-empty.
read_calendar_settings() {  # $1 = conf, $2 = report bad lines
    local conf="$1" warn="$2" line kind rest tok lineno mask a b i d mode
    wd_mask=1111100; obs_mode=nearest; obs_day=-------
    [ -n "$conf" ] && [ -r "$conf" ] || return 0
    lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        line="${line%$'\r'}"; line="${line#$'\xef\xbb\xbf'}"; line="${line%%#*}"
        read -r kind rest <<< "$line"
        case "$kind" in
            workdays)
                mask=0000000
                for tok in ${rest//,/ }; do
                    case "$tok" in
                        [Aa][Ll][Ll]) mask=1111111 ;;
                        *-*) a=$(dow_num "${tok%%-*}"); b=$(dow_num "${tok#*-}")
                             if [ -n "$a" ] && [ -n "$b" ]; then
                                 i=$a
                                 while :; do mask=$(str_set "$mask" "$i" 1); [ "$i" = "$b" ] && break; i=$((i % 7 + 1)); done
                             else [ -n "$warn" ] && echo "calendar: line $lineno: unknown day range '$tok'" >&2; fi ;;
                        *)   a=$(dow_num "$tok")
                             if [ -n "$a" ]; then mask=$(str_set "$mask" "$a" 1)
                             else [ -n "$warn" ] && echo "calendar: line $lineno: unknown day '$tok'" >&2; fi ;;
                    esac
                done
                if [ "$mask" = 0000000 ]; then [ -n "$warn" ] && echo "calendar: line $lineno: no workdays named, line ignored" >&2
                else wd_mask=$mask; fi ;;
            observe)
                for tok in $rest; do
                    case "$tok" in
                        nearest|next|prev|none) obs_mode=$tok ;;
                        *=nearest|*=next|*=prev|*=none)
                            d=$(dow_num "${tok%%=*}")
                            case "${tok#*=}" in nearest) mode='~' ;; next) mode='>' ;; prev) mode='<' ;; none) mode=x ;; esac
                            if [ -n "$d" ]; then obs_day=$(str_set "$obs_day" "$d" "$mode")
                            else [ -n "$warn" ] && echo "calendar: line $lineno: unknown day in '$tok'" >&2; fi ;;
                        *) [ -n "$warn" ] && echo "calendar: line $lineno: unknown observe option '$tok'" >&2 ;;
                    esac
                done ;;
        esac
    done < "$conf"
    if [ -n "$warn" ]; then
        for d in 1 2 3 4 5 6 7; do
            [ "${obs_day:$((d - 1)):1}" != - ] && is_workday "$wd_mask" "$d" \
                && echo "calendar: observe $(dow_abbr "$d" | tr 'A-Z' 'a-z')=... has no effect: $(dow_abbr "$d") is a workday" >&2
        done
    fi
    return 0
}

# Evaluate every entry in $1 for each year in $2..: prints "YYYY-MM-DD<TAB>rule
# year<TAB>name<TAB>note", where note is empty, "observed from DOW MM-DD" for
# a shifted yearly rule, or "not a workday, no effect". Entries on workdays
# are placed first across ALL the years, then the yearly rules that fell on
# non-workdays are shifted in date order onto workdays not already taken, so
# chaining works across New Year's (a Saturday Jan 1 shifted back onto a
# Dec 31 the file also lists moves on to Dec 30; a Sunday Dec 31 shifted
# forward past Jan 1 lands on Jan 2). Callers pass the neighbouring years.
holidays_for_years() {
    local conf="$1" y line kind f1 f2 f3 rest name d dow n mm dim first ld ldow day lineno skipwhy
    local used=$'\n' deferred="" i warn warnyear s e se ee mode step orig odow fwd back k
    shift
    [ -n "$conf" ] && [ -r "$conf" ] || return 0
    warnyear="${2:-$1}"   # report bad lines for the year of interest (the middle one), once
    read_calendar_settings "$conf" "${CALENDAR_VERBOSE:-}"
    for y in "$@"; do
        lineno=0
        warn=""; [ "$y" = "$warnyear" ] && warn="${CALENDAR_VERBOSE:-}"
        while IFS= read -r line || [ -n "$line" ]; do
            lineno=$((lineno + 1))
            line="${line%$'\r'}"
            line="${line#$'\xef\xbb\xbf'}"   # UTF-8 BOM on the first line
            line="${line%%#*}"
            read -r kind f1 f2 f3 rest <<< "$line"
            [ -n "$kind" ] || continue
            d=""; dow=""; name=""; skipwhy=""
            case "$kind" in
                workdays|observe) continue ;;   # settings: read_calendar_settings
                fixed)
                    name="$f2 $f3 $rest"
                    case "$f1" in [0-9][0-9]-[0-9][0-9]|[0-9]-[0-9][0-9]|[0-9][0-9]-[0-9]|[0-9]-[0-9]) skipwhy="no such date in $y" ;; *) f1="" ;; esac
                    [ -n "$f1" ] && read -r dow d < <(date -d "$y-$f1" +'%u %F' 2>/dev/null) ;;
                nth)
                    name="$rest"; n="$f1"; dow=$(dow_num "$f2"); mm="$f3"
                    if is_int "$n" && [ "$n" -ge 1 ] && [ -n "$dow" ] && is_int "$mm" \
                       && first=$(date -d "$y-$mm-01" +%u 2>/dev/null) && [ -n "$first" ]; then
                        dim=$(date -d "$y-$mm-01 +1 month -1 day" +%d)
                        n=$((10#$n))
                        day=$(( 1 + (dow - first + 7) % 7 + 7 * (n - 1) ))
                        if [ "$day" -le "$((10#$dim))" ]; then d=$(printf '%s-%02d-%02d' "$y" "$((10#$mm))" "$day")
                        else skipwhy="no such weekday in $y"; fi
                    fi ;;
                last)
                    name="$f3 $rest"; dow=$(dow_num "$f1"); mm="$f2"
                    if [ -n "$dow" ] && is_int "$mm" \
                       && read -r ld ldow < <(date -d "$y-$mm-01 +1 month -1 day" +'%d %u' 2>/dev/null) && [ -n "$ldow" ]; then
                        day=$(( 10#$ld - (ldow - dow + 7) % 7 ))
                        d=$(printf '%s-%02d-%02d' "$y" "$((10#$mm))" "$day")
                    fi ;;
                once)
                    name="$f2 $f3 $rest"
                    name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
                    s="${f1%%..*}"; e="${f1#*..}"
                    se=""; ee=""
                    case "$s" in [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) se=$(date -d "$s" +%s 2>/dev/null) ;; esac
                    case "$e" in [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ee=$(date -d "$e" +%s 2>/dev/null) ;; esac
                    if [ -z "$se" ] || [ -z "$ee" ]; then skipwhy="cannot parse"
                    elif [ "$ee" -lt "$se" ]; then skipwhy="range ends before it starts"
                    elif [ $(( (ee - se) / 86400 )) -gt 366 ]; then skipwhy="range longer than a year"
                    elif [ "$y" -lt "$((10#${s%%-*}))" ] || [ "$y" -gt "$((10#${e%%-*}))" ]; then
                        continue   # another year entirely: fine, not ours
                    else
                        while [ "$se" -le "$ee" ]; do
                            read -r d dow < <(date -d "@$se" +'%F %u')
                            se=$((se + 86400))
                            [ "${d%%-*}" = "$y" ] || continue
                            case "$used" in *$'\n'"$d"$'\n'*) continue ;; esac
                            used="$used$d"$'\n'
                            if is_workday "$wd_mask" "$dow"; then printf '%s\t%s\t%s\t\n' "$d" "$y" "${name:-holiday}"
                            else printf '%s\t%s\t%s\t%s\n' "$d" "$y" "${name:-holiday}" "not a workday, no effect"; fi
                        done
                        continue
                    fi ;;
            esac
            if [ -z "$d" ]; then
                [ -n "$warn" ] && echo "calendar: skipping line $lineno (${skipwhy:-cannot parse}): $line" >&2
                continue
            fi
            name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
            if ! is_workday "$wd_mask" "$dow"; then
                # Non-workday: decided in pass 2, once every year's workday
                # holidays are known.
                deferred="$deferred$d	$dow	$y	${name:-holiday}"$'\n'
                continue
            fi
            case "$used" in *$'\n'"$d"$'\n'*) continue ;; esac   # same date listed twice
            used="$used$d"$'\n'
            printf '%s\t%s\t%s\t\n' "$d" "$y" "${name:-holiday}"
        done < "$conf"
    done
    # Pass 2: observe the yearly rules that fell on non-workdays, earliest
    # first, per the observe policy for that day.
    [ -n "$deferred" ] || return 0
    while IFS=$'\t' read -r d dow y name; do
        [ -n "$d" ] || continue
        mode="${obs_day:$((dow - 1)):1}"
        case "$mode" in '~') mode=nearest ;; '>') mode=next ;; '<') mode=prev ;; x) mode=none ;; -) mode=$obs_mode ;; esac
        if [ "$mode" = none ]; then printf '%s\t%s\t%s\t%s\n' "$d" "$y" "$name" "not a workday, no effect"; continue; fi
        if [ "$mode" = nearest ]; then
            # Distance to the nearest workday each way; ties go forward.
            k=$dow; fwd=0;  while [ "$fwd" -lt 7 ];  do k=$((k % 7 + 1)); fwd=$((fwd + 1));   is_workday "$wd_mask" "$k" && break; done
            k=$dow; back=0; while [ "$back" -lt 7 ]; do k=$(((k + 5) % 7 + 1)); back=$((back + 1)); is_workday "$wd_mask" "$k" && break; done
            mode=next; [ "$back" -lt "$fwd" ] && mode=prev
        fi
        step="+1 day"; [ "$mode" = prev ] && step="-1 day"
        orig="$d"; odow="$dow"
        for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
            d=$(date -d "$d $step" +%F)
            dow=$(date -d "$d" +%u)
            is_workday "$wd_mask" "$dow" && case "$used" in *$'\n'"$d"$'\n'*) ;; *) break ;; esac
        done
        used="$used$d"$'\n'
        printf '%s\t%s\t%s\t%s\n' "$d" "$y" "$name" "observed from $(dow_abbr "$odow") ${orig#*-}"
    done < <(printf '%s' "$deferred" | sort -u -t $'\t' -k1,1)
}

# Days-of-month (space separated) that are holidays in $1-$2 (YYYY MM).
# Any failure -> empty (no holidays).
holidays_in_month() {
    local y=$((10#$1)) m="$2"
    holidays_for_years "$CALENDAR" $((y - 1)) $y $((y + 1)) 2>/dev/null \
        | awk -F'\t' -v ym="$1-$m" 'substr($1,1,7)==ym {print substr($1,9,2)+0}' \
        | sort -un | tr '\n' ' '
}

# Workdays from day-of-month $3 (a $4, 1..7) through day $5, given the workday
# mask $1 and the holiday days-of-month $2. Walked in awk: no per-day subprocesses.
count_workdays() {
    awk -v mask="$1" -v hol="$2" -v from="$3" -v dow="$4" -v dim="$5" 'BEGIN{
        hn=split(hol, ha, " "); for(i=1; i<=hn; i++) H[ha[i]+0]=1
        n=0; w=dow; for(d=from; d<=dim; d++){ if(substr(mask,w,1)=="1" && !H[d]) n++; w=w%7+1 }
        print n }'
}

if [ "${1:-}" = "--calendar" ]; then
    case "${2:-}" in ''|[0-9][0-9][0-9][0-9]) ;; *) echo "usage: $0 --calendar [YYYY]" >&2; exit 2 ;; esac
    y=$((10#${2:-$(bdate +%Y)}))
    if [ -z "$CALENDAR" ]; then echo "calendar: disabled (CLAUDE_BUDGET_CALENDAR=$CLAUDE_BUDGET_CALENDAR): workdays mon-fri, no holidays"
    elif [ ! -r "$CALENDAR" ]; then echo "calendar: no file at $CALENDAR: workdays mon-fri, no holidays"
    fi
    read_calendar_settings "$CALENDAR" ""
    days=""; for d in 1 2 3 4 5 6 7; do is_workday "$wd_mask" "$d" && days="$days $(dow_abbr "$d")"; done
    echo "workdays:${days}"
    obs="$obs_mode"
    for d in 1 2 3 4 5 6 7; do
        case "${obs_day:$((d - 1)):1}" in '~') obs="$obs $(dow_abbr "$d")=nearest" ;; '>') obs="$obs $(dow_abbr "$d")=next" ;; '<') obs="$obs $(dow_abbr "$d")=prev" ;; x) obs="$obs $(dow_abbr "$d")=none" ;; esac
    done
    echo "observe:  $obs"
    CALENDAR_VERBOSE=1 holidays_for_years "$CALENDAR" $((y - 1)) $y $((y + 1)) \
        | awk -F'\t' -v y="$y" '$2==y' | sort \
        | while IFS=$'\t' read -r d _ name note; do
              printf '%s %s %s%s\n' "$d" "$(date -d "$d" +%a)" "$name" "${note:+ ($note)}"
          done
    if [ "$y" = "$(bdate +%Y)" ]; then
        m=$(bdate +%m); dom=$(bdate +%-d); dow=$(bdate +%u)
        dim=$(date -d "$y-$m-01 +1 month -1 day" +%-d); first=$(date -d "$y-$m-01" +%u)
        hol=$(holidays_in_month "$y" "$m")
        printf '%s: %s workdays, %s remaining\n' "$(bdate +'%B %Y')" \
            "$(count_workdays "$wd_mask" "$hol" 1 "$first" "$dim")" \
            "$(count_workdays "$wd_mask" "$hol" "$dom" "$dow" "$dim")"
    fi
    exit 0
fi

input=$(cat)
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || input='{}'   # garbage stdin: render an empty line, quietly

# ANSI color codes
CLR_DIM=$'\033[2m'
CLR_RESET=$'\033[0m'

# Shared heat ramp (24-bit truecolor): muted green -> Claude gold -> Claude coral,
# as channel arrays plus the percentage each stop is anchored at. Both the effort
# level and the progress bars draw from this, so their colors line up.
# Anchored on Claude Code's own tokens: gold #fab219 (warning) + coral #ff5858 (error).
#
# The 5/95 anchors (rather than 0/100) inset the endpoints just enough that full
# coral means ">=95%" instead of "exactly 100%" -- the alarm saturates while you can
# still act on it. Clamping outside the anchors is continuous in color and only puts
# a corner in the rate of change, so the small flat zones cost nothing in smoothness.
RAMP_R=(107 250 255)   # #6bb85f  #fab219  #ff5858
RAMP_G=(184 178  88)
RAMP_B=( 95  25  88)
RAMP_AT=(  5  50  95)

# Map a 0-100 percentage to a continuously interpolated ramp color. Single source
# of truth for the bars, so they all read on the same scale.
# Pure bash integer math (no subshell) since this runs on every render.
ramp_color() {
    local p="${1:-0}"
    p="${p%%.*}"; [ -z "$p" ] && p=0
    (( p < 0 )) && p=0
    (( p > 100 )) && p=100

    local last=$(( ${#RAMP_AT[@]} - 1 ))
    local r g b
    if (( p <= RAMP_AT[0] )); then
        r=${RAMP_R[0]}; g=${RAMP_G[0]}; b=${RAMP_B[0]}
    elif (( p >= RAMP_AT[last] )); then
        r=${RAMP_R[last]}; g=${RAMP_G[last]}; b=${RAMP_B[last]}
    else
        # Find the segment containing p, then lerp each channel across it.
        local i=0
        while (( p > RAMP_AT[i+1] )); do i=$(( i + 1 )); done
        local span=$(( RAMP_AT[i+1] - RAMP_AT[i] ))
        local t=$(( p - RAMP_AT[i] ))
        r=$(( RAMP_R[i] + (RAMP_R[i+1] - RAMP_R[i]) * t / span ))
        g=$(( RAMP_G[i] + (RAMP_G[i+1] - RAMP_G[i]) * t / span ))
        b=$(( RAMP_B[i] + (RAMP_B[i+1] - RAMP_B[i]) * t / span ))
    fi
    # A real ESC byte, like the CLR_* constants: the final render prints the
    # line with printf '%s', so text from the input can't smuggle escapes in.
    printf $'\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}

# Map an effort level to its ramp color by sampling the ramp at evenly spaced
# points, so the five levels stay visually distinct and stay in sync with the bars
# automatically if the stops above ever change. Unknown -> dim.
effort_color() {
    case "$1" in
        low)    ramp_color   0 ;;
        medium) ramp_color  25 ;;
        high)   ramp_color  50 ;;
        xhigh)  ramp_color  75 ;;
        max)    ramp_color 100 ;;
        *)      printf '%s' "$CLR_DIM" ;;
    esac
}

# Build an ASCII progress bar with the percentage shown after the bar: bar <pct> <width>
# e.g. bar 42 10 -> █████░░░░░ 42%  (width = number of block characters)
# Fill color: continuous green -> gold -> coral ramp, see ramp_color().
# Percentages over 100 peg the fill and keep counting in the label.
bar() {
    local pct="${1:-0}"
    local width="${2:-10}"

    local pct_int
    pct_int=$(printf '%.0f' "$pct")

    # Filled and empty block counts based on full width
    local filled=$(printf '%.0f' "$(echo "$pct $width" | awk '{printf "%f", $1 * $2 / 100}')")
    [ "$filled" -gt "$width" ] && filled=$width
    [ "$filled" -lt 0 ] && filled=0
    local empty=$(( width - filled ))

    local fill_str empty_str color
    fill_str=''; for ((i=0; i<filled; i++)); do fill_str+='█'; done
    empty_str=''; for ((i=0; i<empty; i++)); do empty_str+='░'; done

    # Pick color from the shared ramp (matches the effort levels).
    local color
    color=$(ramp_color "$pct_int")

    # Colored filled blocks, then plain empty blocks, then space and percentage
    printf "${color}%s${CLR_RESET}%s %s%%" "$fill_str" "$empty_str" "$pct_int"
}

# Format a dollar amount compactly: <1000 -> $123, >=1000 -> $1.3k
fmt_money() {
    awk -v v="$1" 'BEGIN{
        if (v >= 1000) printf "$%.1fk", v/1000;
        else if (v >= 10) printf "$%.0f", v;
        else printf "$%.2f", v;
    }'
}

# --- Daily + monthly spend from the usage endpoint (cached, background) ---
# The same data /usage renders: GET api.anthropic.com/api/oauth/usage with the
# CLI's own OAuth token. .spend.used is the month-to-date dollars the page
# shows and .spend.limit is the org's monthly cap — real billed numbers, so no
# local token pricing to drift.
# The endpoint has no per-day figure, so today's spend is derived: the month
# total the first time each day is seen becomes that day's baseline
# (cache/statusline/budget-usage.daystart), and daily = month - baseline. Accurate from the first
# refresh of the day; a month rollover (month < baseline) resets the baseline.
#
# CLOCK: the day bar and the workday count run on the budget clock:
# CLAUDE_BUDGET_TZ if set (any TZ name, e.g. UTC or America/New_York), else
# local time. The month figure is server-side and unaffected. The page has no
# per-day number to reconcile against, so "today" is the calendar day on that
# clock: on local time an 8 PM session counts as that day's spend against
# that day's allowance, not the next UTC day's. Only wrinkle: the page's
# month counter resets at 00:00 UTC on the last day, so if the budget clock
# lags UTC that evening's baseline re-pins via the month<baseline guard and
# the day bar shows only post-reset spend until midnight.
is_num() { case "$1" in ''|*[!0-9.]*|*.*.*|.) return 1 ;; *) return 0 ;; esac; }
MONTHLY_LIMIT="${CLAUDE_BUDGET_MONTHLY_LIMIT:-0}"   # your own monthly target; 0 = use the response's limit
is_num "$MONTHLY_LIMIT" || MONTHLY_LIMIT=0
# Cache lives INSIDE the config dir (not ~/.cache) so a devcontainer that mounts
# ~/.claude gets the credentials, the cache, and the day-start baseline together.
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CACHE_DIR="$CLAUDE_DIR/cache/statusline"
CACHE_FILE="$CACHE_DIR/budget-usage"
BASE_FILE="$CACHE_DIR/budget-usage.daystart"
LOCK_DIR="$CACHE_DIR/budget-usage.lock"
HOLD_FILE="$CACHE_DIR/budget-usage.hold"   # epoch before which no fetch is attempted (after a failure)
REFRESH_INTERVAL="${CLAUDE_BUDGET_REFRESH:-60}"   # seconds between usage fetches
is_int "$REFRESH_INTERVAL" || REFRESH_INTERVAL=60
[ "$REFRESH_INTERVAL" -ge 10 ] || REFRESH_INTERVAL=10
mkdir -p "$CACHE_DIR" 2>/dev/null

now=$(date +%s)
today=$(bdate +%Y-%m-%d)

# Fetch month-to-date spend and cache it as
# "<date> <fetched-epoch> <today-dollars> <month-dollars> <limit-dollars> <workday-mask> <holiday-days-of-month...>".
# Runs detached. Any failure keeps the stale cache and writes a hold so the
# next renders don't retry until the refresh interval has passed (5 minutes
# after an HTTP 429).
hold() { printf '%s\n' "$(( now + ${1:-$REFRESH_INTERVAL} ))" > "$HOLD_FILE" 2>/dev/null; }
refresh_usage() {
    local creds="$CLAUDE_DIR/.credentials.json"
    [ -r "$creds" ] || { hold; return; }
    local tok exp
    tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds" 2>/dev/null)
    [ -n "$tok" ] || { hold; return; }
    # Expired token (expiresAt is epoch milliseconds): the CLI refreshes the
    # credentials file on its own; serve the stale cache until it does. A
    # missing or unreadable expiry is treated as "try".
    exp=$(jq -r '(.claudeAiOauth.expiresAt? // empty) | numbers | floor' "$creds" 2>/dev/null)
    if [ -n "$exp" ] && ! [ "$exp" -gt "$(( now * 1000 ))" ] 2>/dev/null; then hold; return; fi
    local resp code
    # The token travels in a curl config piped from the printf builtin: never
    # in argv (ps), never in a temp file (a heredoc would be one on bash < 5.1).
    # The HTTP status rides as the last line of the output.
    resp=$(printf '%s\n' 'url = "https://api.anthropic.com/api/oauth/usage"' \
                          "header = \"Authorization: Bearer $tok\"" \
                          'header = "anthropic-beta: oauth-2025-04-20"' \
           | curl -s -m 5 -w '\n%{http_code}' -K -) || { hold; return; }
    code="${resp##*$'\n'}"; resp="${resp%$'\n'*}"
    if [ "$code" = 429 ]; then hold 300; return; fi
    [ -n "$resp" ] || { hold; return; }
    local month limit
    read -r month limit <<< "$(printf '%s' "$resp" | jq -r '
        if (.spend.used.amount_minor? // null) != null then
            "\((.spend.used.amount_minor // 0) / 100) \((.spend.limit.amount_minor // .spend.cap.credits.amount_minor // 0) / 100)"
        else empty end' 2>/dev/null)"
    [ -n "$month" ] || { hold; return; }
    # Your own target wins over the org's; neither -> 0 -> bars hidden.
    awk -v l="$MONTHLY_LIMIT" 'BEGIN{exit !(l > 0)}' && limit="$MONTHLY_LIMIT"
    awk -v l="$limit" 'BEGIN{exit !(l > 0)}' || limit=0
    # Day-start baseline: first sighting of a budget-clock day pins the month total.
    local b_date b_month
    read -r b_date b_month < "$BASE_FILE" 2>/dev/null
    if [ "$b_date" != "$today" ] || ! awk -v m="$month" -v b="${b_month:-0}" 'BEGIN{exit !(m >= b)}'; then
        b_month="$month"
        printf '%s %s\n' "$today" "$b_month" > "$BASE_FILE" 2>/dev/null
    fi
    local day
    day=$(awk -v m="$month" -v b="$b_month" 'BEGIN{d=m-b; if(d<0)d=0; printf "%.6g", d}')
    # This month's workday mask and holidays (days-of-month) from config/calendar.conf.
    local hol
    read_calendar_settings "$CALENDAR" ""
    hol=$(holidays_in_month "$(bdate +%Y)" "$(bdate +%m)")
    printf '%s %s %s %s %s %s %s\n' "$today" "$now" "$day" "$month" "$limit" "$wd_mask" "$hol" > "$CACHE_FILE.tmp" 2>/dev/null \
        && mv "$CACHE_FILE.tmp" "$CACHE_FILE" 2>/dev/null && rm -f "$HOLD_FILE" 2>/dev/null
}

# Read the cache. Its age comes from the stamp inside the line, not the file's
# mtime, so nothing here depends on stat(1).
day_cost=""; mo_cost=""; hol_doms=""; wd_mask=""; cache_age=""
if [ -f "$CACHE_FILE" ]; then
    read -r c_date c_stamp c_day c_mo c_lim c_mask c_hol < "$CACHE_FILE" 2>/dev/null
    # Yesterday's cache would misreport its daily total as today's: hide instead.
    # A garbled line (non-numeric fields, or one from before the workday mask
    # existed) is treated as no cache, so the next render refreshes it.
    if [ "$c_date" = "$today" ] && is_num "$c_day" && is_num "$c_mo" && is_mask "$c_mask"; then
        is_int "$c_stamp" && cache_age=$(( now - c_stamp ))
        day_cost="$c_day"; mo_cost="$c_mo"; wd_mask="$c_mask"; hol_doms="$c_hol"
        is_num "$c_lim" && awk -v l="$c_lim" 'BEGIN{exit !(l+0 > 0)}' 2>/dev/null && MONTHLY_LIMIT="$c_lim"
    fi
fi

# Decide whether to trigger a background refresh: no usable cache, or one
# older than the interval (a future stamp = clock skew, also stale), and no
# hold from a recent failed fetch.
hold_until=$(cat "$HOLD_FILE" 2>/dev/null); is_int "$hold_until" || hold_until=0
if { [ -z "$cache_age" ] || [ "$cache_age" -ge "$REFRESH_INTERVAL" ] || [ "$cache_age" -lt 0 ]; } \
   && [ "$now" -ge "$hold_until" ]; then
    # Clear a stale lock (crashed/killed refresher) so refreshes can't wedge
    # permanently. The lock's own stamp file dates it; rename-then-remove so
    # two renders can't both claim it.
    if [ -d "$LOCK_DIR" ]; then
        lock_stamp=$(cat "$LOCK_DIR/stamp" 2>/dev/null); is_int "$lock_stamp" || lock_stamp=0
        [ $(( now - lock_stamp )) -gt 300 ] && mv "$LOCK_DIR" "$LOCK_DIR.stale.$$" 2>/dev/null && rm -rf "$LOCK_DIR.stale.$$" 2>/dev/null
    fi
    # mkdir is atomic: only one refresher runs at a time.
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$now" > "$LOCK_DIR/stamp" 2>/dev/null
        ( refresh_usage; rm -rf "$LOCK_DIR" 2>/dev/null ) >/dev/null 2>&1 &
        disown 2>/dev/null
    fi
fi

# --- Budget math ---
day_pct=""; mo_pct=""; day_allow=""; mo_over=0; day_label="day:"
# No known limit (response had none, no override): the bars stay hidden.
if [ -n "$day_cost" ] && awk -v l="$MONTHLY_LIMIT" 'BEGIN{exit !(l > 0)}' 2>/dev/null; then
    # Remaining WORKdays in the month, today included. The workday mask and
    # this month's holidays (days-of-month) arrive pre-derived in the cache
    # (see refresh_usage). On a non-workday today contributes nothing and the
    # count is the workdays still ahead (its spend draws on the next workday's
    # slice); floor at 1 so the last day of the month never divides by zero.
    dom=$(bdate +%-d); dow=$(bdate +%u)
    wd=$(count_workdays "$wd_mask" "$hol_doms" "$dom" "$dow" "$(date -d "$(bdate +%Y-%m-01) +1 month -1 day" +%-d)")
    [ "$wd" -ge 1 ] 2>/dev/null || wd=1
    # The cue that today's allowance is borrowed from the next workday.
    is_workday "$wd_mask" "$dow" || day_label="off:"
    case " $hol_doms " in *" $dom "*) day_label="off:" ;; esac
    read -r day_pct day_allow mo_pct mo_over <<< "$(awk \
        -v d="$day_cost" -v m="$mo_cost" -v lim="$MONTHLY_LIMIT" -v wd="$wd" 'BEGIN{
        rem = lim - (m - d)              # month budget left as of this morning
        allow = rem / wd                 # today fair share of what remains
        if (allow <= 0) { dp = (d > 0.005) ? 999 : 0; allow = 0 }
        else { dp = d * 100 / allow; if (dp > 999) dp = 999 }
        mp = m * 100 / lim; if (mp > 999) mp = 999
        over = m - lim; if (over < 0) over = 0
        printf "%d %.6g %d %.6g", dp, allow, mp, over
    }')"
fi

# Model info
model=$(echo "$input" | jq -r '.model.display_name // empty')

# Reasoning effort level (low | medium | high | xhigh | max)
effort=$(echo "$input" | jq -r '.effort.level // empty')

# Context usage
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty | numbers')

# Session cost (real-time, already in the input)
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

# Location + session churn
cur_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

# --- Responsive bar widths: bars fill the terminal width ---
# The statusline runs as a piped command (no controlling TTY), but Claude Code
# exports the terminal width as $COLUMNS. Fall back to tput, then to 80.
cols="${COLUMNS:-0}"
[ "$cols" -gt 0 ] 2>/dev/null || cols=$(tput cols 2>/dev/null || echo 80)

# COLUMNS is the raw terminal width, but the fullscreen TUI doesn't give the
# statusline all of it: the frame (border + padding) eats ~4 columns. Reserve
# those plus one spare so the right edge never truncates.
RESERVE=5
avail=$(( cols - RESERVE ))

# All bars render at ONE shared width so they read on the same visual scale:
# 16 blocks by default, stretched or squeezed together so the line fills the
# terminal. The floor is 10 blocks -- one block per 10%, the coarsest a bar
# still carries real information; rather than squeeze below it we wrap to two
# rows (and only a terminal too narrow even for that renders floor-width bars
# that overflow).
BAR_NOM=16; BAR_MIN=10

# Precompute the variable-length text pieces so we can measure the fixed
# "chrome" (everything that isn't bar blocks) exactly.
[ -n "$session_cost" ] && session_money=$(fmt_money "$session_cost") || session_money=""
ctx_i=$( [ -n "$used_pct" ] && printf '%.0f' "$used_pct" || echo "" )

have_ctx=0; have_day=0; have_mo=0
[ -n "$used_pct" ] && have_ctx=1
[ -n "$day_pct" ]  && have_day=1
[ -n "$mo_pct" ]   && have_mo=1

# Money annotations: spent/allotted beside each budget bar, plus a coral
# overage tag on the month once past the limit.
day_money=""; mo_money=""; over_str=""
if [ "$have_day" = 1 ]; then
    day_money=$(fmt_money "$day_cost")
    # An exhausted month has no allowance to show a denominator for.
    awk -v a="$day_allow" 'BEGIN{exit !(a > 0)}' && day_money="$day_money/$(fmt_money "$day_allow")"
fi
if [ "$have_mo" = 1 ]; then
    mo_money="$(fmt_money "$mo_cost")/$(fmt_money "$MONTHLY_LIMIT")"
    awk -v o="$mo_over" 'BEGIN{exit !(o > 0)}' && over_str="+$(fmt_money "$mo_over")"
fi

# --- Per-piece visible "chrome" widths (everything that isn't bar blocks) ---
# Only "·" is multibyte; " · " is counted as the constant 3, the rest is ASCII,
# so ${#...} is a correct column count regardless of locale.
model_w=0
if [ -n "$model" ]; then
    model_w=${#model}
    [ -n "$effort" ] && model_w=$(( model_w + 3 + ${#effort} ))       # " · <effort>"
fi
ctx_chrome=0
if [ "$have_ctx" = 1 ]; then
    ctx_chrome=$(( 4 + 1 + ${#ctx_i} + 1 ))                           # "ctx:" + " NN%"
    [ -n "$session_money" ] && ctx_chrome=$(( ctx_chrome + 1 + ${#session_money} ))
fi
day_chrome=0
[ "$have_day" = 1 ] && day_chrome=$(( 4 + 1 + ${#day_pct} + 1 ))      # "day:"/"off:" + " NN%"
[ -n "$day_money" ] && day_chrome=$(( day_chrome + 1 + ${#day_money} ))
mo_chrome=0
[ "$have_mo" = 1 ]  && mo_chrome=$(( 6 + 1 + ${#mo_pct} + 1 ))        # "month:" + " NN%"
[ -n "$mo_money" ]  && mo_chrome=$(( mo_chrome + 1 + ${#mo_money} ))
[ -n "$over_str" ]  && mo_chrome=$(( mo_chrome + 1 + ${#over_str} ))
SEP=3   # width of " | "

# Budget segment: day and month share one " | "-delimited segment, with a space between.
budget_chrome=0; have_budget=0
if [ "$have_day" = 1 ] || [ "$have_mo" = 1 ]; then
    have_budget=1
    [ "$have_day" = 1 ] && budget_chrome=$(( budget_chrome + day_chrome ))
    if [ "$have_mo" = 1 ]; then
        [ "$have_day" = 1 ] && budget_chrome=$(( budget_chrome + 1 ))  # space between day and month
        budget_chrome=$(( budget_chrome + mo_chrome ))
    fi
fi

# Shared bar width for a row: split the column budget evenly across its bars,
# clamped to the floor. The division remainder (at most nbars-1 columns) is left
# unfilled rather than making one bar wider than its siblings.
# Args: <budget> <nbars>. Echoes the width.
equal_width() {
    local budget=$1 n=$2 w
    w=$(( budget / n ))
    (( w < BAR_MIN )) && w=$BAR_MIN
    echo "$w"
}

# --- Segment builders (return the colored text for one segment) ---
build_model() {
    [ -z "$model" ] && return
    local s="$model"
    [ -n "$effort" ] && s="$s ${CLR_DIM}·${CLR_RESET} $(effort_color "$effort")$effort${CLR_RESET}"
    printf '%s' "$s"
}
build_ctx() {   # $1 = bar width
    [ "$have_ctx" = 1 ] || return
    local s="ctx:$(bar "$used_pct" "$1")"
    [ -n "$session_money" ] && s="$s ${CLR_DIM}${session_money}${CLR_RESET}"
    printf '%s' "$s"
}
build_budget() {  # $1 = day width, $2 = mo width
    local s=""
    if [ "$have_day" = 1 ]; then
        s="$day_label$(bar "$day_pct" "$1")"
        [ -n "$day_money" ] && s="$s ${CLR_DIM}${day_money}${CLR_RESET}"
    fi
    if [ "$have_mo" = 1 ]; then
        s="$s month:$(bar "$mo_pct" "$2")"
        [ -n "$mo_money" ] && s="$s ${CLR_DIM}${mo_money}${CLR_RESET}"
        [ -n "$over_str" ] && s="$s $(ramp_color 100)${over_str}${CLR_RESET}"
    fi
    printf '%s' "${s# }"
}
# Render a "+A/-R" pair with zero sides suppressed (nothing at all when both
# are zero). $1=added $2=removed $3=style: "hot" (green/coral, the actionable
# pair) or "dim" (ambient context).
fmt_pair() {
    local a="${1:-0}" r="${2:-0}" style="$3" out=""
    [ "$a" -gt 0 ] 2>/dev/null || a=0
    [ "$r" -gt 0 ] 2>/dev/null || r=0
    (( a == 0 && r == 0 )) && return
    local pc mc
    if [ "$style" = hot ]; then pc="$(ramp_color 0)" mc="$(ramp_color 100)"; else pc="$CLR_DIM" mc="$CLR_DIM"; fi
    (( a > 0 )) && out="${pc}+${a}${CLR_RESET}"
    if (( r > 0 )); then
        [ -n "$out" ] && out="$out${CLR_DIM}/${CLR_RESET}"
        out="$out${mc}-${r}${CLR_RESET}"
    fi
    printf '%s' "$out"
}

# Parse `git diff --shortstat` on stdin -> "added removed" (0 0 when empty).
parse_shortstat() {
    awk '{for(i=1;i<=NF;i++){if($(i+1)~/insertion/)a=$i; if($(i+1)~/deletion/)d=$i}} END{printf "%d %d", a, d}'
}

# Location line grammar: path, branch, then facts ordered now -> ambient:
#   ~/git/x ⎇ branch pending +A/-R ↑a↓b · vs <default> +A/-R · session +A/-R
# Every group is self-hiding (pending only when dirty, arrows only with a
# nonzero count against upstream, vs-<default> only off the default branch,
# session only with churn), so the quiet state collapses to "path ⎇ branch".
# "pending" folds untracked-file lines (gitignore respected; text files under 1 MB) into added; its
# presence IS the dirty flag. "behind" is as of the last fetch -- we never
# fetch here. Not width-managed: the TUI truncates rows on its own.
build_locline() {
    local dir="${cur_dir:-$PWD}"
    # ~-shorten; past 35 chars squeeze middle components fish-style (~/g/project)
    # so a deep cwd can't push the interesting right side of the line off-screen.
    local disp="${dir/#$HOME/\~}"
    if [ ${#disp} -gt 35 ]; then
        disp=$(p="$disp" awk 'BEGIN{n=split(ENVIRON["p"],a,"/"); o=a[1]; for(i=2;i<n;i++) o=o"/"substr(a[i],1,1); print o"/"a[n]}')
    fi
    local s="${CLR_DIM}${disp}${CLR_RESET}"

    local branch shown a r pair
    branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
        # Cap the shown name so a long branch can't evict the groups after it.
        shown="$branch"
        [ ${#shown} -gt 26 ] && shown="${shown:0:24}.."
        # Remote repo name, dim, only when it differs from the repo root's
        # dirname (e.g. a checkout whose directory is named differently from the repo).
        local top repo
        top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
        repo=$(git -C "$dir" remote get-url origin 2>/dev/null)
        repo=${repo##*/}; repo=${repo%.git}
        [ -n "$repo" ] && [ "$repo" != "${top##*/}" ] && s="$s ${CLR_DIM}(${repo})${CLR_RESET}"

        # Two spaces after ⎇ — the glyph's overhang visually eats one.
        s="$s ⎇  ${shown}"

        # pending: uncommitted lines vs HEAD + lines in untracked files
        read -r a r <<< "$(git -C "$dir" diff --shortstat HEAD 2>/dev/null | parse_shortstat)"
        local u
        # Only text files under 1 MB count, so a stray build artifact or a
        # not-yet-ignored data dump can't turn every render into a disk scan.
        # ls-files emits repo-relative paths, so the pipeline runs from the repo.
        u=$( (cd "$dir" 2>/dev/null && git ls-files --others --exclude-standard -z 2>/dev/null \
               | xargs -0 sh -c 'find "$@" -maxdepth 0 -type f -size -1024k -print0' sh 2>/dev/null \
               | xargs -0 grep -Ic '' 2>/dev/null) | awk -F: '{s+=$NF} END{print s+0}' )
        pair=$(fmt_pair $(( a + u )) "$r" hot)
        local cluster=""
        [ -n "$pair" ] && cluster="${CLR_DIM}pending${CLR_RESET} $pair"

        # ahead/behind upstream
        local behind ahead arrows=""
        read -r behind ahead <<< "$(git -C "$dir" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)"
        [ "${ahead:-0}" -gt 0 ] 2>/dev/null && arrows="↑$ahead"
        [ "${behind:-0}" -gt 0 ] 2>/dev/null && arrows="$arrows↓$behind"
        [ -n "$arrows" ] && cluster="${cluster:+$cluster }$arrows"

        # one separator for the whole working-state cluster, matching the
        # dim · that introduces the vs/session groups
        [ -n "$cluster" ] && s="$s ${CLR_DIM}·${CLR_RESET} $cluster"

        # vs default branch (origin/HEAD, falling back to main/master), hidden on it
        local def
        def=$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
        def=${def#origin/}
        if [ -z "$def" ]; then
            if git -C "$dir" show-ref --verify -q refs/heads/main; then def=main
            elif git -C "$dir" show-ref --verify -q refs/heads/master; then def=master; fi
        fi
        if [ -n "$def" ] && [ "$branch" != "$def" ]; then
            # A clone that only checked out a feature branch has origin/main but no local main.
            local defref="$def"
            git -C "$dir" show-ref --verify -q "refs/heads/$def" || defref="origin/$def"
            read -r a r <<< "$(git -C "$dir" diff --shortstat "$defref...HEAD" 2>/dev/null | parse_shortstat)"
            pair=$(fmt_pair "$a" "$r" dim)
            [ -n "$pair" ] && s="$s ${CLR_DIM}· vs ${def}${CLR_RESET} $pair"
        fi
    fi

    pair=$(fmt_pair "$lines_added" "$lines_removed" dim)
    [ -n "$pair" ] && s="$s ${CLR_DIM}· session${CLR_RESET} $pair"
    printf '%s' "$s"
}
join_parts() {  # join non-empty args with " | "
    local out="" p
    for p in "$@"; do [ -z "$p" ] && continue; [ -n "$out" ] && out="$out | "; out="$out$p"; done
    printf '%s' "$out"
}

# --- One line, or two? Split only when a single row can't fit even with every
#     bar at its floor width. ---
nparts=0
[ -n "$model" ]         && nparts=$(( nparts + 1 ))
[ "$have_ctx" = 1 ]     && nparts=$(( nparts + 1 ))
[ "$have_budget" = 1 ]  && nparts=$(( nparts + 1 ))
one_fixed=$(( model_w + ctx_chrome + budget_chrome ))
[ "$nparts" -gt 1 ] && one_fixed=$(( one_fixed + (nparts - 1) * SEP ))
nbars=$(( have_ctx + have_day + have_mo ))
min_bars=$(( nbars * BAR_MIN ))

BAR_W=$BAR_NOM

if [ $(( one_fixed + min_bars )) -le "$avail" ]; then
    # ---------- ONE LINE: split the row's budget evenly across all bars ----------
    [ "$nbars" -gt 0 ] && BAR_W=$(equal_width $(( avail - one_fixed )) "$nbars")
    out=$(join_parts "$(build_model)" "$(build_ctx "$BAR_W")" "$(build_budget "$BAR_W" "$BAR_W")")
else
    # ---------- TWO LINES: identity+context on row 1, day+month budget on row 2 ----------
    # Each row could afford a different width; the tighter row sets the shared
    # width so bars still match across rows (the roomier row runs short).
    l1_nparts=0; [ -n "$model" ] && l1_nparts=$(( l1_nparts + 1 )); [ "$have_ctx" = 1 ] && l1_nparts=$(( l1_nparts + 1 ))
    l1_fixed=$(( model_w + ctx_chrome )); [ "$l1_nparts" -gt 1 ] && l1_fixed=$(( l1_fixed + SEP ))

    l2_nbars=$(( have_day + have_mo ))

    w1=""; w2=""
    [ "$have_ctx" = 1 ]   && w1=$(equal_width $(( avail - l1_fixed )) 1)
    [ "$l2_nbars" -gt 0 ] && w2=$(equal_width $(( avail - budget_chrome )) "$l2_nbars")
    if [ -n "$w1" ] && [ -n "$w2" ]; then
        BAR_W=$(( w1 < w2 ? w1 : w2 ))
    elif [ -n "$w1" ]; then BAR_W=$w1
    elif [ -n "$w2" ]; then BAR_W=$w2
    fi

    line1=$(join_parts "$(build_model)" "$(build_ctx "$BAR_W")")
    line2=$(build_budget "$BAR_W" "$BAR_W")

    out="$line1"
    if [ -n "$line2" ]; then [ -n "$out" ] && out="$out"$'\n'"$line2" || out="$line2"; fi
fi

# Location + git + churn get their own final row unless switched off.
case "${CLAUDE_BUDGET_REPO_LINE:-on}" in
    0|off|no|false) ;;
    *) loc_line=$(build_locline)
       [ -n "$loc_line" ] && out="$out"$'\n'"$loc_line" ;;
esac

printf '%s' "$out"
