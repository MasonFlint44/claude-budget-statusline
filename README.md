# claude-budget-statusline

A two-line statusline for Claude Code: model, effort, context use, session
cost and two budget bars on the first line; directory, branch and diff on the
second (switch the second line off with `CLAUDE_BUDGET_REPO_LINE=off`). The
budget bars:

- **day** — today's spend against today's allowance. The allowance divides the
  month's *remaining* budget evenly over the remaining workdays of the month
  (weekdays minus holidays), so a heavy day early in the month shrinks the days
  after it, and a quiet day gives the rest of the month room.
- **month** — month-to-date spend against the monthly limit. Past the limit
  the bar pegs and shows the overage.

Both read the same numbers the `/usage` page shows, so there is no local token
pricing to drift. This is for organization or Team accounts with spend
billing, where the `/usage` page shows dollars; see Prerequisites.

> **Note on the data source.** The script calls `api.anthropic.com/api/oauth/usage`
> with the CLI's own OAuth token — the same request the `/usage` command makes.
> The token is read from the CLI's credentials file, sent only to that host, and
> never written to disk or logged; the cache holds dollar totals only. The
> endpoint is not publicly documented and may change without notice; if it
> does, the budget bars go blank and the rest of the line keeps working. This
> project is not affiliated with or supported by Anthropic.

## Install

**As a Claude Code plugin** (the repo is one): add it from a marketplace that
lists it, then run `/install-statusline`. The skill copies the files to
`~/.claude/statusline/` and adds the `statusLine` line to your settings, showing
you the change before writing it. Re-run after a plugin update to refresh the
copy. Plugins can't set `statusLine` themselves and the plugin directory moves
on each version update, which is why the install step exists.

**By hand:** copy the `statusline/` directory somewhere stable, keeping its
`config/` subfolder (the script finds it relative to itself),
then add to `~/.claude/settings.json`:

```json
"statusLine": { "command": "bash /path/to/statusline/budget-statusline.sh" }
```

No restart needed: Claude Code picks up the change on its next refresh. The
first render shows blanks for the budget bars; they fill within a minute once
the background fetch has run.

## Files

| File | Purpose |
|------|---------|
| `statusline/budget-statusline.sh` | the statusline itself |
| `statusline/config/holidays.conf` | the holiday calendar — ships with the US federal holidays; edit to match your company's, add your own closures or PTO as `date` lines. Yours once installed: the installer never overwrites it |

Holiday rules are one per line: `fixed MM-DD`, `nth N DOW MM`, `last DOW MM`,
or `date YYYY-MM-DD`, each followed by a name. An `observe` line says how a
fixed date that lands on a weekend is observed, per weekend day: `prev` or
`next` move it to the nearest working day in that direction that isn't already
a holiday (so Christmas and Boxing Day chain onto Monday and Tuesday), `none`
leaves it. Common settings:

| | |
|---|---|
| `observe sat=prev sun=next` | US federal (the default) |
| `observe sat=next sun=next` | UK, Ireland, Australia, New Zealand, Canada |
| `observe sat=none sun=next` | Japan |
| `observe none` | no substitution (most of continental Europe) |

To check the calendar:

```
bash statusline/budget-statusline.sh --holidays 2027
```

## Prerequisites

- **A Claude Code login through claude.ai on a plan that reports dollar
  spend.** The budget bars read the CLI's OAuth token from
  `~/.claude/.credentials.json` and need the usage response to carry a
  month-to-date dollar figure, which organization plans with spend billing
  do. With an API key there is no token; with a plan whose `/usage` page
  shows no dollar amount there is no figure. In both cases the bars stay
  hidden and the rest of the line still renders.
- `bash`, `jq`, `curl`, `awk`, and GNU `date`, `stat`, `readlink`.
- `git` — only for the branch and diff segment; blank without it.

Linux and devcontainers work as-is. **macOS:** the script uses GNU `date -d`,
`stat -c`, and `readlink -f`. Install coreutils (`brew install coreutils`) and
either put the `g`-prefixed tools first on `PATH` or alias `date`, `stat`, and
`readlink` to `gdate`, `gstat`, `greadlink` for the script. Untested on macOS;
in particular, if Claude Code keeps the token in the Keychain rather than the
credentials file there, the bars will stay hidden.

## How the daily number works

The usage endpoint has no per-day figure, so the script derives one: the first
time it sees a new calendar day it records the month-to-date total as that
day's baseline, and daily = month − baseline. Accurate from the first refresh
of the day. The day rolls at **local midnight** unless `CLAUDE_BUDGET_TZ` says
otherwise; the month figure is server-side and rolls at 00:00 UTC on the last
day. Cache and baseline live in
`~/.claude/cache/statusline/` (inside the config dir so a devcontainer that
mounts `~/.claude` carries them along).

## Knobs

- `CLAUDE_BUDGET_MONTHLY_LIMIT` — your own monthly target in dollars. Set, it
  is the limit the bars use even if the org's is higher; unset, the limit in
  the usage response is used. With neither the budget bars stay hidden.
- `CLAUDE_BUDGET_TZ` — the clock the day bar and workday count run on, as a
  time zone name (`UTC`, `America/New_York`). Default: local time.
- `CLAUDE_BUDGET_REFRESH` — seconds between usage fetches. Default 60. The
  fetch runs detached and never blocks a render.
- `CLAUDE_BUDGET_HOLIDAYS` — path to a holiday rules file, if not the default;
  `off` disables holidays entirely (every weekday counts as a workday).
- `CLAUDE_BUDGET_REPO_LINE` — `off` hides the second line (directory, branch,
  diff), leaving only the first. Default on.
- `CLAUDE_CONFIG_DIR` — honored, same as Claude Code.

Set knobs in the environment Claude Code starts from, or inline in the
`statusLine` command, e.g. `"command": "CLAUDE_BUDGET_TZ=UTC bash /path/to/budget-statusline.sh"`.

## License

MIT — see `LICENSE`.
