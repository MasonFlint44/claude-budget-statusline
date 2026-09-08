expect "$(cat "$CFG/statusline/config/calendar.conf")" "$MINE"   # the edited calendar survives an update
cmp -s "$CFG/statusline/spend-statusline.sh" "$REPO/statusline/spend-statusline.sh" || { echo "    script was not refreshed"; fail=$((fail + 1)); }
expect "$(jq -r .statusLine.command "$CFG/settings.json")" "bash $CFG/statusline/spend-statusline.sh"
expect "$(cat "$CFG/statusline/config/display.conf")" "$MYDISPLAY"   # the edited display file survives an update
