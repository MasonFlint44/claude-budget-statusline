---
name: install-statusline
description: Install or update the budget statusline — copies the statusline files to a stable location under ~/.claude and wires statusLine in settings.json. Re-run after a plugin update to refresh the copy.
---

# Install the budget statusline

Plugins cannot set `statusLine` themselves, and the plugin's own directory moves on every version update, so this skill copies the files somewhere stable and points settings at that copy. Idempotent: safe to re-run after a plugin update.

## Steps

1. **Locate the source.** The files ship with this plugin at `${CLAUDE_PLUGIN_ROOT}/statusline/`:
   - `budget-statusline.sh`
   - `scripts/holidays.py`
   - `config/holidays.conf` (the shared holiday calendar)
   - `config/extra-days-off.txt` (the user's own days off)

   Resolve the config dir as `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`; call it `$CFG` below.

2. **Copy to the stable location**, preserving the subfolders:
   ```bash
   CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
   mkdir -p "$CFG/statusline/scripts" "$CFG/statusline/config"
   cp "${CLAUDE_PLUGIN_ROOT}/statusline/budget-statusline.sh" "$CFG/statusline/"
   cp "${CLAUDE_PLUGIN_ROOT}/statusline/scripts/holidays.py" "$CFG/statusline/scripts/"
   cp "${CLAUDE_PLUGIN_ROOT}/statusline/config/holidays.conf" "$CFG/statusline/config/"
   [ -e "$CFG/statusline/config/extra-days-off.txt" ] || \
     cp "${CLAUDE_PLUGIN_ROOT}/statusline/config/extra-days-off.txt" "$CFG/statusline/config/"
   chmod +x "$CFG/statusline/budget-statusline.sh"
   ```
   The script, the holiday engine, and the shared calendar are refreshed every time. `extra-days-off.txt` is copied only if absent — it holds the user's own days off and must not be overwritten on update.

3. **Check prerequisites** and report any that are missing: `bash`, `jq`, `curl`, `git`; `python3` is optional (without it the day bar counts plain weekdays). On macOS, warn that the script needs GNU `date`, `stat`, and `readlink` (`brew install coreutils`, then the `g`-prefixed tools first on `PATH` or aliased).

4. **Wire settings.** Read `$CFG/settings.json`. Show the user the exact change before making it, then set:
   ```json
   "statusLine": { "command": "bash <CFG>/statusline/budget-statusline.sh" }
   ```
   with `<CFG>` expanded to the real path. If a different `statusLine` is already set, say so and ask before replacing it. Never touch any other key.

5. **Tell the user** to restart Claude Code. The budget bars show blank on the first render and fill within a minute once the background refresh has run. Point them at the plugin's `README.md` for what the bars mean and the knobs (`CLAUDE_BUDGET_MONTHLY_LIMIT`, `CLAUDE_BUDGET_HOLIDAYS`, `CLAUDE_BUDGET_EXTRA_DAYS`).

## Do not

- Do not point `statusLine` at the plugin directory — it changes on update.
- Do not overwrite an existing `extra-days-off.txt`.
- Do not edit settings without showing the change first.
