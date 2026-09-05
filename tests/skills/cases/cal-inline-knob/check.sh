expect_file "$CFG/team-calendar.conf" "^once[[:space:]]+2026-12-24[[:space:]]" "the closure did not land in the calendar the statusLine command names"
expect "$(cat "$CFG/statusline/config/calendar.conf")" "$ORIG"   # the default-path file must be untouched
