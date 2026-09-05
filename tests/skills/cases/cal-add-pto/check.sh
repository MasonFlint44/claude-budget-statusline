expect_file "$CFG/statusline/config/calendar.conf" "^once[[:space:]]+2026-09-14\.\.2026-09-18[[:space:]]"
expect_no_warnings
expect "$(cat "$REPO/statusline/config/calendar.conf")" "$SHIPPED"   # the plugin copy is never edited
expect_out "14"
