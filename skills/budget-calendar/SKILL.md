---
name: budget-calendar
description: View or edit the budget statusline's calendar — the work week, holidays, PTO and closures that the daily allowance is spread over. Use when the user wants to add time off ("I'm off next week", "add PTO"), change which days they work ("we work Sunday to Thursday", "I have Fridays off"), add or remove a holiday, change how holidays on non-workdays are observed, or see the calendar ("show my budget calendar", "how many workdays are left this month").
---

# Edit the budget calendar

The statusline spreads the month's remaining budget over the remaining workdays, and `calendar.conf` defines what a workday is. This skill translates what the user wants into the file's grammar, edits the installed copy, and shows the resulting calendar so mistakes are visible immediately.

## Where the file is

The installed copy is `$CFG/statusline/config/calendar.conf` with `CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`, next to the installed script `$CFG/statusline/budget-statusline.sh`. **Edit only that copy.** The plugin's own `statusline/config/calendar.conf` is the shipped default, is replaced on every plugin update, and is never read by the installed statusline — editing it changes nothing. If `CLAUDE_BUDGET_CALENDAR` is set in the environment or inline in the `statusLine` command in `$CFG/settings.json`, the file it names is the one in use instead. If the installed file does not exist, say so and point the user at `/install-statusline`.

## The grammar

One entry per line, `#` starts a comment, names run to the end of the line:

| Line | Meaning |
|------|---------|
| `workdays DAYS` | the days the user works: a wrapping range (`mon-fri`, `sun-thu`), a list (`mon,tue,wed,thu`), a mix (`mon-wed,fri`) or `all`. Default `mon-fri`. Last line wins |
| `observe MODE [DOW=MODE ...]` | how a yearly holiday on a non-workday is observed: `nearest` (nearest workday, ties forward; the default), `next`, `prev`, `none`. `DOW=MODE` overrides one day. Substitutes skip days already holidays |
| `fixed MM-DD name` | yearly holiday on a fixed date |
| `nth N DOW MM name` | Nth weekday of a month (`nth 4 thu 11 Thanksgiving Day`) |
| `last DOW MM name` | last weekday of a month |
| `once YYYY-MM-DD[..YYYY-MM-DD] name` | a one-off date or inclusive range. Never shifted; one on a non-workday has no effect |

Yearly rules follow the observe policy. `once` lines are literal, so a PTO range may include a weekend without side effects.

## Steps

1. **Show the current state.** Run the listing and show the user its output:
   ```bash
   bash "$CFG/statusline/budget-statusline.sh" --calendar
   ```
   It prints the work week, the observe policy, this year's holidays with their observed dates, warnings for lines that don't parse, and this month's total and remaining workday counts. Pass a year (`--calendar 2027`) to check another year. For a pure "show me" request, stop here.

2. **Translate the request into exact lines.** Resolve relative dates against today's date on the budget clock (`CLAUDE_BUDGET_TZ` if set, else local). Typical translations:
   - "I'm off the 14th through the 18th" → `once 2026-09-14..2026-09-18 PTO`
   - "Company closed Dec 24" → `once 2026-12-24 Office closed`
   - "I don't work Fridays" → `workdays mon-thu`
   - "We work Sunday to Thursday" → `workdays sun-thu`
   - "Add Boxing Day" → `fixed 12-26 Boxing Day`
   - "UK rules for weekend holidays" → `observe next`
   - Removing a holiday → delete its line (or comment it out with `#` if the user may want it back).

   When the work week changes, check the `observe` line with the user: `nearest` adapts automatically, but explicit `DOW=MODE` overrides may now name workdays (the listing warns) or be missing for the new off days.

3. **Confirm before writing.** Show the exact lines to add, change or remove, and where in the file. Write only after the user agrees. Append `once` lines at the end of the file; keep `workdays` and `observe` near the top where the shipped file has them.

4. **Verify.** Rerun the listing from step 1 and show the output. Every warning must be either resolved or explained; a new entry must appear on the expected date with the expected tag. If something is wrong, fix the line and rerun.

5. **Report** what changed in one or two sentences. The statusline picks the file up on its next background refresh (within about a minute), no restart needed.

## Do not

- Do not edit the plugin's copy of `calendar.conf` or the script itself.
- Do not write without showing the exact lines first.
- Do not invent holidays the user did not ask for, and do not rewrite lines that are not part of the request.
- Do not skip the verification listing.
