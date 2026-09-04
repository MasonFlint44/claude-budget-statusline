# claude-budget-statusline

A one-line statusline for Claude Code that shows model, effort, context use,
session cost, git state, and two budget bars:

- **day** — today's spend against today's allowance. The allowance divides the
  month's *remaining* budget evenly over the remaining workdays of the month
  (weekdays minus holidays), so a heavy day early in the month shrinks the days
  after it, and a quiet day gives the rest of the month room.
- **month** — month-to-date spend against the monthly limit. Past the limit
  the bar pegs and shows the overage.

Both read the same numbers the `/usage` page shows, so there is no local token
pricing to drift.

> **Note on the data source.** The script calls `api.anthropic.com/api/oauth/usage`
> with the CLI's own OAuth token — the same request the `/usage` command makes.
> That endpoint is not publicly documented and may change without notice; if it
> does, the budget bars go blank and the rest of the line keeps working.

## Install

**As a Claude Code plugin** (the repo is one): add it from a marketplace that
lists it, then run `/install-statusline`. The skill copies the files to
`~/.claude/statusline/` and adds the `statusLine` line to your settings, showing
you the change before writing it. Re-run after a plugin update to refresh the
copy. Plugins can't set `statusLine` themselves and the plugin directory moves
on each version update, which is why the install step exists.

**By hand:** copy the `statusline/` directory somewhere stable, keeping its
`scripts/` and `config/` subfolders (the script finds them relative to itself),
then add to `~/.claude/settings.json`:

```json
"statusLine": { "command": "bash /path/to/statusline/budget-statusline.sh" }
```

Restart Claude Code. The first render shows blanks for the budget bars; they
fill within a minute once the background refresh has run.

## Files

| File | Purpose |
|------|---------|
| `statusline/budget-statusline.sh` | the statusline itself |
| `statusline/scripts/holidays.py` | evaluates the holiday rules |
| `statusline/config/holidays.conf` | the shared holiday calendar (ships with the US federal holidays; edit to match your company's) |
| `statusline/config/extra-days-off.txt` | your own extra days off — PTO, office closures — one `YYYY-MM-DD` per line; never overwritten by the installer |

Holiday rules are one per line: `fixed MM-DD`, `nth N DOW MM`, `last DOW MM`,
or `date YYYY-MM-DD`, each followed by a name. Fixed dates that land on a
weekend are observed on the nearest weekday. `python3 statusline/scripts/holidays.py 2027`
prints the calendar for a year.

## Prerequisites

`bash`, `jq`, `curl`, `git`, and `python3` (holidays only — without it the day
bar counts plain weekdays).

Linux and devcontainers work as-is. **macOS:** the script uses GNU `date -d`,
`stat -c`, and `readlink -f`. Install coreutils (`brew install coreutils`) and
either put the `g`-prefixed tools first on `PATH` or alias `date`, `stat`, and
`readlink` to `gdate`, `gstat`, `greadlink` for the script.

## How the daily number works

The usage endpoint has no per-day figure, so the script derives one: the first
time it sees a new calendar day it records the month-to-date total as that
day's baseline, and daily = month − baseline. Accurate from the first refresh
of the day. The day rolls at **local midnight**; the month figure is server-side
and rolls at 00:00 UTC on the last day. Cache and baseline live in
`~/.claude/cache/statusline/` (inside the config dir so a devcontainer that
mounts `~/.claude` carries them along).

## Knobs

- `CLAUDE_BUDGET_MONTHLY_LIMIT` — monthly limit in dollars, used when the
  usage response carries none. With no limit from either source the budget
  bars stay hidden.
- `CLAUDE_BUDGET_HOLIDAYS` — path to a holiday rules file, if not the default.
- `CLAUDE_BUDGET_EXTRA_DAYS` — path to the extra-days-off file, if not the default.
- `CLAUDE_CONFIG_DIR` — honored, same as Claude Code.

Refresh interval is 60 s; the refresh runs detached and never blocks a render.

## Development

Run `scripts/install-hook.sh` once after cloning: it installs a pre-commit
hook that runs [gitleaks](https://github.com/gitleaks/gitleaks) over the staged
diff, since this script handles an OAuth token.

## License

MIT — see `LICENSE`.
