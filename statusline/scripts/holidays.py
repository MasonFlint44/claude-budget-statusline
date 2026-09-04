#!/usr/bin/env python3
"""Observed holiday calendar driven by a small rules file — standard library
only, so it travels with budget-statusline.sh on its own.

Rules live in config/holidays.conf (one per line, "#" comments):

    fixed MM-DD        name   fixed date; Saturday -> Friday, Sunday -> Monday
    nth   N DOW MM     name   Nth weekday of a month  (DOW = mon..sun, N = 1..5)
    last  DOW MM       name   last weekday of a month
    date  YYYY-MM-DD   name   a one-off date (no weekend shift)

The shipped file is the US federal calendar. Replace it with your company's.
Personal days off (PTO, closures) go in config/extra-days-off.txt instead.
"""

import os
import sys
from datetime import date, timedelta

DOW = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}
DEFAULT_RULES = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "..", "config", "holidays.conf")


def nth_weekday(year, month, weekday, n):
    """Date of the nth <weekday> (0=Mon) of a month."""
    d = date(year, month, 1)
    offset = (weekday - d.weekday()) % 7
    return d + timedelta(days=offset + 7 * (n - 1))


def last_weekday_of(year, month, weekday):
    d = date(year, month + 1, 1) - timedelta(days=1) if month < 12 \
        else date(year, 12, 31)
    return d - timedelta(days=(d.weekday() - weekday) % 7)


def observed(d):
    """Fixed-date shift: Saturday -> preceding Friday, Sunday -> following
    Monday."""
    if d.weekday() == 5:
        return d - timedelta(days=1)
    if d.weekday() == 6:
        return d + timedelta(days=1)
    return d


def load_rules(path=None):
    """Parse the rules file -> list of (kind, args, name). Bad lines are
    skipped with a note on stderr rather than breaking the calendar."""
    rules = []
    with open(path or DEFAULT_RULES) as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            kind = parts[0].lower()
            try:
                if kind == "fixed":
                    m, d = (int(x) for x in parts[1].split("-"))
                    rules.append((kind, (m, d), " ".join(parts[2:])))
                elif kind == "nth":
                    rules.append((kind, (int(parts[1]), DOW[parts[2].lower()],
                                         int(parts[3])), " ".join(parts[4:])))
                elif kind == "last":
                    rules.append((kind, (DOW[parts[1].lower()], int(parts[2])),
                                  " ".join(parts[3:])))
                elif kind == "date":
                    rules.append((kind, date.fromisoformat(parts[1]),
                                  " ".join(parts[2:])))
                else:
                    raise ValueError("unknown rule kind")
            except (IndexError, KeyError, ValueError) as e:
                print(f"holidays: skipping line {lineno} ({e}): {raw.rstrip()}",
                      file=sys.stderr)
    return rules


def observed_holidays(year, rules_path=None):
    """Observed holidays for a year -> {date: name}."""
    out = {}
    for kind, args, name in load_rules(rules_path):
        if kind == "fixed":
            out[observed(date(year, *args))] = name or "holiday (observed)"
        elif kind == "nth":
            n, dow, month = args
            out[nth_weekday(year, month, dow, n)] = name or "holiday"
        elif kind == "last":
            dow, month = args
            out[last_weekday_of(year, month, dow)] = name or "holiday"
        elif kind == "date" and args.year == year:
            out[args] = name or "holiday"
    return out


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    conf = next((a.split("=", 1)[1] for a in sys.argv[1:]
                 if a.startswith("--rules=")), None)
    y = int(args[0]) if args else date.today().year
    for d, name in sorted(observed_holidays(y, conf).items()):
        print(d, d.strftime("%a"), name)
