#!/usr/bin/env bats
# The prompt-cache cue after the ctx bar: "cache 42m" while the conversation's
# cached prefix is warm, "cache cold ↻38k" once it has expired, from the
# prompt_cache object Claude Code sends after the first response.
load helpers
setup() { fresh_config; cache_line "$NOW" "3.25 120 400 1111100 7"; }
# pc OBSERVED WARM TTL EXPIRES-IN-SECONDS [RECACHE]: stdin JSON with a ctx bar,
# a session cost and a prompt_cache block whose expiry is relative to NOW.
pc() {
    local exp=null rc=null
    [ "$4" != null ] && exp=$(( $(epoch_at "$NOW") + $4 ))
    [ -n "${5:-}" ] && rc="$5"
    printf '{"context_window":{"used_percentage":12},"cost":{"total_cost_usd":1.5},"prompt_cache":{"caching_observed":%s,"warm":%s,"ttl":"%s","expires_at":%s,"recache_tokens_if_cold":%s}}' "$1" "$2" "$3" "$exp" "$rc"
}

@test "warm: minutes left, rounded up, dim, after the session cost with a dot between" {
    INPUT="$(pc true true 1h 2500)" render "$NOW"; assert_has '12% $1.50 · cache 42m |'
    INPUT="$(pc true true 1h 3600)" render "$NOW"; assert_has 'cache 60m'
}
@test "under a minute: seconds" {
    INPUT="$(pc true true 1h 50)" render "$NOW"; [[ "$output" =~ cache\ (4[89]|50)s ]] || { echo "no seconds in: $output"; false; }
}
@test "gold in the last five minutes of a 1h TTL, the last minute of a 5m TTL; dim before that" {
    local gold; gold=$(at "$NOW" bash -c 'printf "\033[38;2;250;178;25m"')
    INPUT="$(pc true true 1h 250)" render_raw "$NOW"; assert_has "${gold}cache 5m"
    INPUT="$(pc true true 1h 304)" render_raw "$NOW"; assert_has $'\033[2mcache 6m'   # 304, not 301: the fake clock can run a second or two ahead
    INPUT="$(pc true true 5m 200)" render_raw "$NOW"; assert_has $'\033[2mcache 4m'
    INPUT="$(pc true true 5m 50)" render_raw "$NOW"; [[ "$output" =~ "${gold}cache "(4[89]|50)s ]] || { echo "not gold: $output"; false; }
    INPUT="$(pc true true 2h 250)" render_raw "$NOW"; assert_has "${gold}cache 5m"   # an unknown TTL gets the 1h window
}
@test "cold: coral, with the tokens the next request re-caches" {
    INPUT="$(pc true false 1h null 38412)" render_raw "$NOW"; assert_has $'\033[38;2;255;88;88mcache cold ↻38k\033[0m'
    INPUT="$(pc true false 1h null 812)" render "$NOW"; assert_has 'cache cold ↻812'
    INPUT="$(pc true false 1h null 1500)" render "$NOW"; assert_has 'cache cold ↻2k'
}
@test "cold with no re-cache figure (right after a compaction, or zero): just 'cache cold'" {
    INPUT="$(pc true false 1h null)" render "$NOW"; assert_has 'cache cold |'
    INPUT="$(pc true false 1h null 0)" render "$NOW"; assert_has 'cache cold |'
}
@test "warm but already past its expiry (a stale render), or warm with no expiry: cold" {
    INPUT="$(pc true true 1h -5 38412)" render "$NOW"; assert_has 'cache cold ↻38k'
    INPUT="$(pc true true 1h 0)" render "$NOW"; assert_has 'cache cold'
    INPUT="$(pc true true 1h null)" render "$NOW"; assert_has 'cache cold'
}
@test "no cue before caching has been observed, without a prompt_cache block, or without a ctx bar" {
    INPUT="$(pc false true 1h 2500)" render "$NOW"; assert_lacks "cache"
    INPUT='{"context_window":{"used_percentage":12},"cost":{"total_cost_usd":1.5}}' render "$NOW"; assert_lacks "cache"
    INPUT='{"model":{"display_name":"Opus"},"prompt_cache":{"caching_observed":true,"warm":false}}' render "$NOW"; assert_lacks "cache"
}
@test "without a session cost the cue follows the percentage" {
    INPUT='{"context_window":{"used_percentage":12},"prompt_cache":{"caching_observed":true,"warm":false}}' render "$NOW"
    assert_has '12% · cache cold |'
}
@test "the dot and the warm cue are dim; the cold cue's arrow is one column" {
    INPUT="$(pc true true 1h 2500)" render_raw "$NOW"
    assert_has $'\033[2m$1.50\033[0m \033[2m·\033[0m \033[2mcache 42m\033[0m'
}
@test "the cue is part of the row's width: bars shrink to make room, and the wider cold form tips the row into two" {
    local full='{"model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":42.6},"cost":{"total_cost_usd":1234.5},"prompt_cache":{"caching_observed":true,"warm":%s,"ttl":"1h","expires_at":%s,"recache_tokens_if_cold":38412}}'
    local exp=$(( $(epoch_at "$NOW") + 2500 ))
    INPUT="$(printf "$full" true "$exp")" COLUMNS_OVERRIDE=120 render "$NOW"
    [ "${#lines[@]}" = 1 ]; [ "${#lines[0]}" -le 115 ]; assert_has "cache 42m |"
    [[ "${lines[0]}" =~ ctx:([█░]+) ]]; assert_equal "${#BASH_REMATCH[1]}" 11
    [[ "${lines[0]}" =~ month:([█░│]+) ]]; assert_equal "${#BASH_REMATCH[1]}" 11
    INPUT="$(printf "$full" false null)" COLUMNS_OVERRIDE=120 render "$NOW"
    [ "${#lines[@]}" = 2 ]; [[ "${lines[0]}" == *"cache cold ↻38k" ]]; [ "${#lines[0]}" -le 115 ]; [ "${#lines[1]}" -le 115 ]
    INPUT="$(printf "$full" true "$exp")" COLUMNS_OVERRIDE=100 render "$NOW"
    [ "${#lines[@]}" = 2 ]; [[ "${lines[0]}" == *"cache 42m" ]]; [ "${#lines[0]}" -le 95 ]
}
