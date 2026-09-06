scaffold_installed
printf "# stale marker\n" >> "$CFG/statusline/budget-statusline.sh"
printf "once 2026-11-27 Day after Thanksgiving\n" >> "$CFG/statusline/config/calendar.conf"; MINE=$(cat "$CFG/statusline/config/calendar.conf")
printf "hide pace\n" >> "$CFG/statusline/config/display.conf"; MYDISPLAY=$(cat "$CFG/statusline/config/display.conf")
