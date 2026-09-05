expect_file "$CFG/statusline/config/calendar.conf" "^workdays[[:space:]]+sun-thu[[:space:]]*$"
expect_no_file_match "$CFG/statusline/config/calendar.conf" "^workdays[[:space:]]+mon-fri" "the old workdays line is still active"
expect_file "$CFG/statusline/config/calendar.conf" "^fixed[[:space:]]+12-25" "the shipped holidays were dropped"
expect_no_warnings
