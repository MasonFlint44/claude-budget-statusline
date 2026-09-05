expect_out "Thanksgiving"; expect_out "17"   # the listing content reached the user (17 workdays remain in Sept 2026)
expect "$(cat "$CFG/statusline/config/calendar.conf")" "$ORIG"   # a pure show must not write
