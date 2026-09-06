expect_file "$CFG/statusline/config/display.conf" "^[[:space:]]*hide[[:space:]].*\bpace\b"
expect "$(cat "$REPO/statusline/config/display.conf")" "$SHIPPED"   # the plugin copy is never edited
expect "$(bash "$CFG/statusline/budget-statusline.sh" --display 2>&1 | grep -c '^pace  *off')" 1
expect "$(bash "$CFG/statusline/budget-statusline.sh" --display 2>&1 | grep -c 'skipping')" 0
expect_out "hidden"   # the report said what happened
