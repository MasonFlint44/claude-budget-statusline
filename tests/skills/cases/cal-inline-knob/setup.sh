scaffold_installed "CLAUDE_BUDGET_CALENDAR=$CFG/team-calendar.conf "
cp "$REPO/statusline/config/calendar.conf" "$CFG/team-calendar.conf"; ORIG=$(cat "$CFG/statusline/config/calendar.conf")
