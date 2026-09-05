expect "$(cat "$CFG/statusline/config/calendar.conf")" "$MINE"   # the edited calendar survives an update
cmp -s "$CFG/statusline/budget-statusline.sh" "$REPO/statusline/budget-statusline.sh" || { echo "    script was not refreshed"; fail=$((fail + 1)); }
expect "$(jq -r .statusLine.command "$CFG/settings.json")" "bash $CFG/statusline/budget-statusline.sh"
