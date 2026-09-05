---
name: install-statusline
description: Install or update the budget statusline — copies the statusline files to a stable location under ~/.claude and wires statusLine in settings.json. Re-run after a plugin update to refresh the copy.
disable-model-invocation: true
---

# Install the budget statusline

Plugins cannot set `statusLine` themselves, and the plugin's own directory moves on every version update, so this skill copies the files somewhere stable and points settings at that copy. Idempotent: safe to re-run after a plugin update.

## Steps

1. **Locate the source.** The files ship with this plugin at `${CLAUDE_PLUGIN_ROOT}/statusline/`:
   - `budget-statusline.sh`
   - `config/calendar.conf` (the work-week and holiday calendar)

   Resolve the config dir as `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`; call it `$CFG` below.

2. **Copy to the stable location**, preserving the subfolders:
   ```bash
   CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
   mkdir -p "$CFG/statusline/config"
   cp "${CLAUDE_PLUGIN_ROOT}/statusline/budget-statusline.sh" "$CFG/statusline/"
   [ -e "$CFG/statusline/config/calendar.conf" ] || \
     cp "${CLAUDE_PLUGIN_ROOT}/statusline/config/calendar.conf" "$CFG/statusline/config/"
   chmod +x "$CFG/statusline/budget-statusline.sh"
   ```
   The script is refreshed every time. `calendar.conf` is copied only if absent — once installed it is the user's own calendar (they may have edited it) and must not be overwritten on update.

3. **Check prerequisites** and report any that are missing: `bash`, `jq`, `curl`, `awk`, `git`, and a claude.ai login (the budget bars need the CLI's OAuth token; with an API key they stay hidden). On macOS, warn that the script needs bash 4.4+ (`brew install bash`, then name that bash in the `statusLine` command: `"command": "/opt/homebrew/bin/bash <CFG>/statusline/budget-statusline.sh"`); the system bash is 3.2.

4. **Wire settings.** Read `$CFG/settings.json`. Show the user the exact change before making it, then set:
   ```json
   "statusLine": { "type": "command", "command": "bash <CFG>/statusline/budget-statusline.sh" }
   ```
   with `<CFG>` expanded to the real path. If a different `statusLine` is already set, say so and ask before replacing it. Never touch any other key.

5. **Tell the user** the new statusline appears on the next refresh, no restart needed (Claude Code picks up the settings change live). The budget bars show blank on the first render and fill within a minute once the background fetch has run. Point them at the plugin's `README.md` for what the bars mean and the knobs (`CLAUDE_BUDGET_MONTHLY_LIMIT`, `CLAUDE_BUDGET_TZ`, `CLAUDE_BUDGET_REFRESH`, `CLAUDE_BUDGET_CALENDAR`, `CLAUDE_BUDGET_REPO_LINE`), and at `/budget-calendar` for editing the calendar (work week, holidays, PTO).

## Do not

- Do not point `statusLine` at the plugin directory — it changes on update.
- Do not overwrite an existing `calendar.conf`.
- Do not edit settings without showing the change first.
