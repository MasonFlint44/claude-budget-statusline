#!/usr/bin/env bats
# The escapes themselves: bar fills and the effort word take their colour
# from one green -> gold -> coral ramp, the annotations are dim, and text
# from the input is printed verbatim (no printf formatting, no escapes).
load helpers
setup() { fresh_config; }
ESC=$'\033'
GREEN="${ESC}[38;2;107;184;95m"; GOLD="${ESC}[38;2;250;178;25m"; CORAL="${ESC}[38;2;255;88;88m"; DIM="${ESC}[2m"; RESET="${ESC}[0m"

@test "a full bar is coral, an empty one green, half way is gold" {
    cache_line "$NOW" "0 400 400 1111100 7"; render_raw "$NOW"
    assert_has "month:${CORAL}█" "off:${GREEN}${RESET}░"
    INPUT='{"context_window":{"used_percentage":50}}' render_raw "$NOW"; assert_has "ctx:${GOLD}█"
}
@test "the ramp saturates at 95% and past 100%" {
    cache_line "$NOW" "50 5000 400 1111100 7"; render_raw "$NOW"; assert_has "month:${CORAL}"
    INPUT='{"context_window":{"used_percentage":95}}' render_raw "$NOW"; assert_has "ctx:${CORAL}"
    INPUT='{"context_window":{"used_percentage":94}}' render_raw "$NOW"; assert_lacks "ctx:${CORAL}"
}
@test "the five effort levels take five distinct ramp colours; an unknown level is dim" {
    local l seen=""
    for l in low medium high xhigh max; do
        INPUT="{\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"$l\"}}" render_raw "$NOW"
        [[ "$output" =~ (${ESC}\[38\;2\;[0-9\;]+m)$l ]] || { echo "no ramp colour before $l in: $output"; false; }
        case "$seen" in *"${BASH_REMATCH[1]}"*) echo "colour of $l repeats an earlier level"; false ;; esac
        seen="$seen ${BASH_REMATCH[1]}"
        case "$l" in low) assert_has "${GREEN}low" ;; max) assert_has "${CORAL}max" ;; esac
    done
    INPUT='{"model":{"display_name":"Opus"},"effort":{"level":"weird"}}' render_raw "$NOW"; assert_has "${DIM}weird${RESET}"
}
@test "money annotations are dim; the overage tag is coral" {
    cache_line "$NOW" "5 450 400 1111100 7"; render_raw "$NOW"
    assert_has "${DIM}\$5.00${RESET}" "${DIM}\$450/\$400${RESET}" "${CORAL}+\$50${RESET}" "${DIM}\$1.50${RESET}"
}
@test "input text is printed verbatim: no printf formatting, no escape smuggling" {
    INPUT='{"model":{"display_name":"Op%s\\033[31mus"},"effort":{"level":"high"}}' render_raw "$NOW"
    assert_has 'Op%s\033[31mus'; assert_lacks "${ESC}[31m"
}
