#!/usr/bin/env python3
"""Render the statusline once, with fixed inputs, and write it as SVG.

The README's preview is generated from the script itself so it cannot drift
from what the code draws. Development-only: needs python3, git and
libfaketime (the clock is pinned to Friday 2026-09-04 14:30 in Chicago).

    docs/preview.py            # writes docs/preview.svg and docs/preview.txt
"""
import html, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SCRIPT = os.path.join(REPO, "statusline", "spend-statusline.sh")
WHEN, TZ, COLS = "2026-09-04 14:30:00", "America/Chicago", 120
# The prompt cache is warm with 42 minutes left (its expiry is relative to WHEN).
INPUT = ('{"model":{"display_name":"Opus"},"effort":{"level":"high"},'
         '"context_window":{"used_percentage":42.6},'
         '"cost":{"total_cost_usd":3.72,"total_lines_added":118,"total_lines_removed":27},'
         '"prompt_cache":{"caching_observed":true,"warm":true,"ttl":"1h","expires_at":%d},'
         '"workspace":{"current_dir":"%s"}}')
# cache: <date> <stamp> <day$> <month$> <limit$> <mask> <holiday doms>
CACHE = "2026-09-04 {stamp} 9.40 143.20 400 1111100 7\n"

def sh(*args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kw).stdout

def main():
    if not shutil.which("faketime"):
        sys.exit("faketime not found (apt install libfaketime)")
    tmp = tempfile.mkdtemp()
    cfg = os.path.join(tmp, "claude"); os.makedirs(os.path.join(cfg, "cache", "statusline"))
    # A repo for the second line: on a feature branch, one commit ahead of main,
    # with uncommitted work.
    work = os.path.join(tmp, "claude-spend-statusline"); os.makedirs(work)
    env_git = {**os.environ, "GIT_AUTHOR_NAME": "p", "GIT_AUTHOR_EMAIL": "p@x", "GIT_COMMITTER_NAME": "p", "GIT_COMMITTER_EMAIL": "p@x"}
    g = lambda *a: sh("git", "-C", work, *a, env=env_git)
    g("init", "-q", "-b", "main")
    open(os.path.join(work, "README.md"), "w").write("hello\n" * 20)
    g("add", "."); g("commit", "-q", "-m", "init")
    g("checkout", "-q", "-b", "feature/preview")
    open(os.path.join(work, "notes.md"), "w").write("x\n" * 30)
    g("add", "."); g("commit", "-q", "-m", "notes")
    open(os.path.join(work, "README.md"), "w").write("hello\n" * 24 + "world\n" * 8)
    open(os.path.join(work, "scratch.txt"), "w").write("y\n" * 4)
    stamp = sh("faketime", WHEN, "date", "+%s", env={**os.environ, "TZ": TZ}).strip()
    open(os.path.join(cfg, "cache", "statusline", "spend-usage"), "w").write(CACHE.format(stamp=stamp))
    env = {**os.environ, "TZ": TZ, "HOME": tmp, "CLAUDE_CONFIG_DIR": cfg, "COLUMNS": str(COLS),
           "CLAUDE_SPEND_REFRESH": "3600", "CLAUDE_SPEND_CALENDAR": os.path.join(REPO, "statusline", "config", "calendar.conf")}
    out = subprocess.run(["faketime", WHEN, "bash", SCRIPT], input=INPUT % (int(stamp) + 2500, work), capture_output=True, text=True, env=env, check=True).stdout
    shutil.rmtree(tmp)
    open(os.path.join(HERE, "preview.txt"), "w").write(re.sub(r"\x1b\[[0-9;]*m", "", out) + "\n")
    open(os.path.join(HERE, "preview.svg"), "w").write(to_svg(out))
    print(re.sub(r"\x1b\[[0-9;]*m", "", out))

FG, DIM_OPACITY, CW, LH, PAD = "#d4d4d4", 0.55, 8.43, 22, 14

def to_svg(text):
    """ANSI (24-bit fg, dim, reset) -> SVG text with one tspan per run."""
    lines = text.split("\n")
    width = max(len(re.sub(r"\x1b\[[0-9;]*m", "", l)) for l in lines)
    w, h = int(width * CW + 2 * PAD), len(lines) * LH + 2 * PAD - 4
    body = []
    for i, line in enumerate(lines):
        fill, dim, spans = FG, False, []
        for tok in re.split(r"(\x1b\[[0-9;]*m)", line):
            if not tok:
                continue
            if tok.startswith("\x1b["):
                codes = tok[2:-1].split(";")
                if codes[:2] == ["38", "2"] and len(codes) == 5:
                    fill = "#%02x%02x%02x" % tuple(int(c) for c in codes[2:5])
                elif codes == ["2"]:
                    dim = True
                elif codes in (["0"], [""]):
                    fill, dim = FG, False
                continue
            attrs = ' fill="%s"' % fill + (' opacity="%s"' % DIM_OPACITY if dim else "")
            spans.append("<tspan%s>%s</tspan>" % (attrs, html.escape(tok)))
        y = PAD + LH * (i + 1) - 6
        body.append('<text x="%d" y="%d" xml:space="preserve">%s</text>' % (PAD, y, "".join(spans)))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
            'font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="14">\n'
            '<rect width="100%%" height="100%%" rx="8" fill="#1e1e1e"/>\n%s\n</svg>\n') % (w, h, w, h, "\n".join(body))

if __name__ == "__main__":
    main()
