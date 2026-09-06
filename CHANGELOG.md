# Changelog

Versions follow the `version` field in `.claude-plugin/plugin.json`; Claude
Code offers a plugin update when that field changes. Each version is a git
tag (`v2.2.0`) and a GitHub release with this section as its notes.

## 2.2.5 — 2026-09-06

- `--doctor` reports `cache: could not write` when the cache directory is not
  writable, instead of reading back an older line as "refreshed just now".
- Tests: a line-trace audit of the suite (207 tests) closed the last untested
  branches: an unknown day in an `observe DOW=MODE` override, the `master`
  default-branch fallback, two-row layouts without a ctx bar, and the
  unwritable cache directory above.
- README: the day-start baseline is per machine.

## 2.2.4 — 2026-09-05

- The bash version guard now points at `brew install bash` and
  `/budget-statusline-install`, which wires the new bash; no hand edit of
  the `statusLine` command is asked of the user.
- Compatibility tests through Docker's `bash` images (`DOCKER=1`, on in CI):
  the version guard verified on real 3.2 and 4.3, a full render on 4.4
  with busybox awk. The 3.2 guard in 2.2.3 was reasoned, not run.

## 2.2.3 — 2026-09-05

- The bash 4.4+ check is now the first command in the script, in bash-3
  syntax, so a too-old bash (macOS's 3.2) gets one clear line with the
  install command instead of a syntax error; 2.2.2's check sat inside
  `--doctor`, past bash-4 syntax, and was unreachable on the bash it was for.
- `/budget-statusline-install` picks the interpreter itself: on macOS it
  wires `/opt/homebrew/bin/bash` or `/usr/local/bin/bash` (4.4+) by absolute
  path, or stops and asks for `brew install bash`; the calendar and doctor
  skills reuse whatever interpreter the `statusLine` command names.

## 2.2.2 — 2026-09-05

- Skills renamed with the plugin's name as prefix, so they cannot collide
  with another statusline plugin's: `/budget-statusline-install`,
  `/budget-statusline-calendar` (was `/budget-calendar`),
  `/budget-statusline-doctor` (was `/budget-doctor`).
- `--doctor` checks the tools first: jq, curl, awk and readlink present,
  bash 4.4+, git optional, and names the install command for the platform
  (apt, dnf, pacman, zypper, apk, brew, winget). A missing jq used to
  surface as a bogus "no OAuth token".
- The headless skill runner bypasses permission prompts (test only), so the
  fresh-install case can wire `settings.json`.

## 2.2.1 — 2026-09-05

- `/install-statusline` is model-invocable again: 2.2.0 marked it
  `disable-model-invocation`, which also stopped "install the budget
  statusline" in chat from reaching it. The slash command and the ask both
  work.

## 2.2.0 — 2026-09-05

- `--doctor`: runs the refresh in the foreground one step at a time and names
  the first one that hides the bars (no credentials, no token, expired token,
  curl failure, HTTP status, spend billing off, no figure, no limit). Exit 1
  when the bars would stay hidden.
- `/budget-doctor` skill: finds the installed script and runs the doctor for
  "my budget bars are blank". The installer now runs the doctor as its last
  step, so the bars are filled on the first render.
- `--help`.
- Staleness tag: a dim `·12m` / `·3h` after the bars once no fetch has
  succeeded for five minutes; counted in the row width so bars shrink to fit.
- macOS: with no credentials file the token is read from the Keychain item
  Claude Code creates. Unverified on a Mac; Linux never touches it.
- README preview generated from the script (`docs/preview.py`).
- `plugin.json` carries author, license, repository and homepage and passes
  `claude plugin validate --strict`.
- shellcheck clean and run in CI. Tests for damaged cache files, 30- and
  20-column terminals, every doctor branch (195 tests).

## 2.1.0 — 2026-09-05

- Amounts honour the `exponent` field of the usage response instead of
  assuming cents.
- Spend billing switched off in the response (`spend.enabled: false`) hides
  the bars instead of showing zeros.
- Recorded usage response as a fixture; `LIVE=1 bats tests/live.bats` probes
  the real endpoint for drift.
- All date arithmetic in bash: no GNU `date`, no `date` calls at all. Render
  path 34 processes down to 6, refresh 81 down to 15.
- The off-words `off|none|no|0|false` work for both `CLAUDE_BUDGET_CALENDAR`
  and `CLAUDE_BUDGET_REPO_LINE`, in any case.
- Headless skill checks (`tests/skills/run.sh`) through `claude -p`.
- Round half up everywhere; locale tests build their own locale.

## 2.0.0 — 2026-09-05

- `calendar.conf` replaces `holidays.conf`: a configurable work week
  (`workdays sun-thu`), observe modes for holidays on non-workdays
  (`nearest`, `next`, `prev`, `none`, per weekday), `once` ranges for PTO.
- `--calendar [YYYY]` listing with observed dates and workday counts.
- `/budget-calendar` skill.
- Bats test suite with golden calendar listings; CI on every push.

## 1.0.0 — 2026-09-03

- Initial public release: day and month budget bars from the usage endpoint,
  US federal holidays, `CLAUDE_BUDGET_TZ`, `CLAUDE_BUDGET_REFRESH`,
  `CLAUDE_BUDGET_MONTHLY_LIMIT`, optional second line, `/install-statusline`.
