#!/usr/bin/env bats
# Golden --calendar listings: one fixture under tests/calendars/ per scenario,
# expected output under tests/expected/. UPDATE=1 rewrites the goldens.
load helpers

# --- the shipped US calendar ---
@test "shipped calendar, 2026" { golden shipped-2026 shipped 2026; }
@test "shipped calendar, 2027: Juneteenth Sat, Jul 4 Sun, Christmas Sat" { golden shipped-2027 shipped 2027; }
@test "shipped calendar, 2022: New Year Sat observed on Fri 2021-12-31" { golden shipped-2022 shipped 2022; }
@test "shipped calendar, no year: current year plus the month line" { golden shipped-current shipped; }

# --- observe policies ---
@test "UK: Christmas Sat + Boxing Day Sun chain to Mon/Tue with next" { golden uk-2027 uk.conf 2027; }
@test "Japan: sat=none loses a Saturday holiday; Sunday one skips the taken Monday" { golden japan-2025 japan.conf 2025; }
@test "Europe: observe none loses weekend holidays" { golden europe-2027 europe.conf 2027; }
@test "seven-day week: nothing is ever shifted" { golden all-2026 all.conf 2026; }

# --- work weeks ---
@test "sun-thu: Friday rule -> Thu, Saturday holiday -> Sun, once range across the weekend" { golden sun-thu-2026 sun-thu.conf 2026; }
@test "mon-thu: three-day weekend, nearest tie goes forward, old two-key overrides" { golden mon-thu-2026 mon-thu.conf 2026; }
@test "workdays mon: chain, then no free workday within two weeks" { golden sparse-2027 sparse.conf 2027; }

# --- once lines ---
@test "holiday observed onto a PTO day stays there; mixed-case modes" { golden pto-chain-2027 pto-chain.conf 2027; }
@test "tabs inside names" { golden pto-chain-2026 pto-chain.conf 2026; }
@test "cross-year range, 2025 side" { golden cross-year-2025 cross-year.conf 2025; }
@test "cross-year range, 2026 side; dangling and half ranges rejected" { golden cross-year-2026 cross-year.conf 2026; }
@test "cross-year range, 2027 side" { golden cross-year-2027 cross-year.conf 2027; }
@test "ranges across DST changes, America/Chicago" { golden dst-chicago dst-ranges.conf 2026; }
@test "ranges across DST changes, Pacific/Auckland" { golden dst-auckland dst-ranges.conf 2026 TZ=Pacific/Auckland; }
@test "ranges across DST changes, Europe/London" { golden dst-london dst-ranges.conf 2026 TZ=Europe/London; }

# --- parser ---
@test "empty file: defaults" { golden empty-2026 empty.conf 2026; }
@test "last workdays/observe line wins; duplicate dates dropped" { golden dupes-2026 dupes.conf 2026; }
@test "nth/last rules, 2026: fifth Friday exists" { golden nth-last-2026 nth-last.conf 2026; }
@test "nth/last rules, 2027: no fifth Friday in May" { golden nth-last-2027 nth-last.conf 2027; }
@test "every warning path" { golden bad-lines-2026 bad-lines.conf 2026; }
@test "a leap-day rule: skipped with a warning in 2027, listed in 2028" { golden leap-2027 leap.conf 2027; golden leap-2028 leap.conf 2028; }
@test "a * in a workdays line does not glob the cwd" { cd "$TESTS_DIR"; golden glob-2026 glob.conf 2026; }
@test "BOM, CRLF, # inside names, bare observe, spaced lists, uppercase keywords" { golden oddities-2026 oddities.conf 2026; }

# --- knob and clock ---
@test "CLAUDE_BUDGET_CALENDAR=off: mon-fri, no holidays" { golden off off 2026; }
@test "missing file: mon-fri, no holidays" { golden missing /nonexistent/calendar.conf 2026; }
@test "month line on local time: Fri 09-04 20:00 Chicago, 18 remaining" { AT="2026-09-04 20:00:00" golden tz-chicago shipped ""; }
@test "month line on the budget clock: same instant is Sat in Auckland, 17 remaining" { AT="2026-09-04 20:00:00" golden tz-auckland shipped "" CLAUDE_BUDGET_TZ=Pacific/Auckland; }
