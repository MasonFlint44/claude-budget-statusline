# claude-budget-statusline

One bash script, `statusline/budget-statusline.sh`, rendered by Claude Code as
the status line, plus four skills under `skills/` that install and configure it.
`README.md` is the user manual and documents every knob and display element.

## Verify before committing

```
bats tests/                        # about 30 s, no network
shellcheck statusline/budget-statusline.sh tests/skills/run.sh tests/skills/triggers.sh tests/bin/curl
UPDATE=1 bats tests/calendar.bats  # only when a golden listing should change; review the diff
DOCKER=1 bats tests/compat.bats    # bash 3.2 / 4.3 / 4.4 images; CI runs this
```

- Every test runs under libfaketime at Saturday 2026-09-05 in America/Chicago,
  and network calls go through the fake `curl` in `tests/bin/`. New tests must
  work under that clock and never reach the real endpoint; `LIVE=1 bats
  tests/live.bats` is the one exception and is for hand use only.
- faketime's clock has about a second of jitter, so boundary tests need a margin
  rather than an exact second.
- The script needs bash 4.4 or newer. Everything before the version guard near
  the top must stay bash 3 syntax so an old macOS bash prints the guard's one
  line instead of a parse error. `compat.bats` checks this.
- `tests/skills/run.sh` runs the skills through `claude -p` for real money and
  copies your credentials into a throwaway config dir; run it by hand, never in CI.
  So does `tests/skills/triggers.sh`, which scores the skill descriptions' triggering
  with the skill-creator plugin's evaluator; run it after changing a description.
- `docs/preview.py` regenerates the README screenshot from the script itself
  (python3, git, libfaketime). Rerun it when the rendered line changes and
  commit the SVG with the change.

## Conventions

- Which elements show is decided by the display file alone; do not add
  per-element environment switches.
- Commits end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`
  and nothing else. No session-link trailer: the repository is public.

## Releasing

1. Add a `## X.Y.Z — YYYY-MM-DD` section to `CHANGELOG.md`.
2. Set `version` in `.claude-plugin/plugin.json` and `VERSION=` near the top of
   the script; `doctor.bats` fails if they differ.
3. Run the checks above, commit, push, and confirm the push landed before
   tagging. Then `git tag -a vX.Y.Z` with the changelog section as the message,
   push the tag, and `gh release create vX.Y.Z` with the same notes.
4. The marketplace (`~/git/claude-toolbox`) carries no version for this plugin, so
   a release never touches it. Locally: `claude plugin update
   budget-statusline@claude-toolbox`, then `/budget-statusline:install` again.
