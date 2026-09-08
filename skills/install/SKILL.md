---
name: install
description: Install or update the spend statusline — copies the statusline files to a stable location under ~/.claude and wires statusLine in settings.json. Use when the user asks to install, set up, enable or update the spend statusline, says the statusline is not showing at all, has just updated the plugin and wants the installed copy refreshed, or wants the statusLine command to run under a different bash (Homebrew's 4.4+ on macOS instead of the system 3.2).
---

# Install the spend statusline

Plugins cannot set `statusLine` themselves, and the plugin's own directory moves on every version update, so this skill copies the files somewhere stable and points settings at that copy. Idempotent: safe to re-run after a plugin update.

## Steps

1. **Locate the source.** The files ship with this plugin at `${CLAUDE_PLUGIN_ROOT}/statusline/`:
   - `spend-statusline.sh`
   - `config/calendar.conf` (the work-week and holiday calendar)
   - `config/display.conf` (which elements the statusline shows)

   Resolve the config dir as `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`; call it `$CFG` below.

2. **Copy to the stable location**, preserving the subfolders:
   ```bash
   CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
   mkdir -p "$CFG/statusline/config"
   cp "${CLAUDE_PLUGIN_ROOT}/statusline/spend-statusline.sh" "$CFG/statusline/"
   [ -e "$CFG/statusline/config/calendar.conf" ] || \
     cp "${CLAUDE_PLUGIN_ROOT}/statusline/config/calendar.conf" "$CFG/statusline/config/"
   [ -e "$CFG/statusline/config/display.conf" ] || \
     cp "${CLAUDE_PLUGIN_ROOT}/statusline/config/display.conf" "$CFG/statusline/config/"
   chmod +x "$CFG/statusline/spend-statusline.sh"
   ```
   The script is refreshed every time. `calendar.conf` and `display.conf` are copied only if absent — once installed they are the user's own (they may have edited them) and must not be overwritten on update.

3. **Pick the bash.** The script needs bash 4.4+. On Linux and in Git Bash on Windows, `bash` is fine. On macOS the system bash is 3.2, and a bare `bash` in the `statusLine` command may resolve to it, so the command must name a newer one by absolute path: check `/opt/homebrew/bin/bash` (Apple silicon) then `/usr/local/bin/bash` (Intel) with `"$candidate" -c 'echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}'`, and use the first that reports 4.4 or newer. If neither exists, stop and tell the user to run `brew install bash`, then re-run this skill; do not wire the system bash. Call the chosen interpreter `<BASH>` below (`bash` outside macOS).

4. **Wire settings.** Read `$CFG/settings.json`. Show the user the exact change before making it, then set:
   ```json
   "statusLine": { "type": "command", "command": "<BASH> <CFG>/statusline/spend-statusline.sh" }
   ```
   with `<BASH>` and `<CFG>` expanded to the real paths. If a different `statusLine` is already set, say so and ask before replacing it. Never touch any other key.

5. **Run the doctor** on the installed copy, with the same interpreter and any inline knobs the `statusLine` command has in front, and show its output:
   ```bash
   <BASH> "$CFG/statusline/spend-statusline.sh" --doctor
   ```
   It checks the tools (jq, curl, awk; a missing one comes with the install command for this platform), the credentials, fetches the usage figures once in the foreground, and ends with `bars: will show` or `bars: hidden` after the step that failed. If the bars will be hidden, explain the failing line (an API-key session has no usage token; a plan with no dollar figure cannot show spend bars; a missing limit needs `CLAUDE_SPEND_MONTHLY_LIMIT`) and point at `/spend-statusline:doctor` for later.

6. **Tell the user** the new statusline appears on the next refresh, no restart needed (Claude Code picks up the settings change live). A successful doctor run has already filled the cache, so the bars show on the first render. Point them at the plugin's `README.md` for what the bars mean and the knobs (`CLAUDE_SPEND_MONTHLY_LIMIT`, `CLAUDE_SPEND_TZ`, `CLAUDE_SPEND_REFRESH`, `CLAUDE_SPEND_CALENDAR`, `CLAUDE_SPEND_DISPLAY`), at `/spend-statusline:calendar` for editing the calendar (work week, holidays, PTO), at `/spend-statusline:display` for hiding or showing elements (the pace tick, the cache cue, the repository row), and at `/spend-statusline:doctor` if the bars ever go blank.

## Do not

- Do not point `statusLine` at the plugin directory — it changes on update.
- Do not overwrite an existing `calendar.conf` or `display.conf`.
- Do not edit settings without showing the change first.
- Do not wire the macOS system bash (3.2); name a 4.4+ bash by absolute path or stop.
