#!/usr/bin/env python3
"""Summarize Luau --coverage (LCOV) output for src/.

Reads an LCOV file (default ./coverage.out, as written by `luau --coverage
test/spec.client.luau`) and reports line coverage for ./src/** only -- the test
harness (spec.luau, sert.luau) is excluded from the denominator.

  stdout : total coverage percentage, one decimal, bare (e.g. "71.0"), so CI
           can capture it -- PCT=$(python3 .github/scripts/coverage.py)
  stderr : a per-file table plus the total -- the human view, for local runs.

This number is HEADLESS-ONLY. Roblox-only paths (Instances, non-number Motion
-- the rtest()s) are skipped headless and read as uncovered; they are exercised
by CI's cloud Roblox job, which has no coverage instrumentation to emit.

Duplicate SF: records (a module required from several places) are merged by
union: a line counts as covered if it was hit in any record.
"""

import sys


def norm(name):
    return name[2:] if name.startswith("./") else name


def parse(path):
    files = {}  # filename -> { line: covered_bool }
    cur = None
    with open(path) as handle:
        for line in handle:
            if line.startswith("SF:"):
                cur = files.setdefault(norm(line[3:].strip()), {})
            elif line.startswith("DA:") and cur is not None:
                ln, hits = line[3:].split(",")[:2]
                ln = int(ln)
                cur[ln] = cur.get(ln, False) or int(hits) > 0
    return files


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "coverage.out"
    try:
        files = parse(path)
    except OSError as err:
        sys.exit(f"coverage: cannot read {path}: {err}")

    src = {name: lines for name, lines in files.items() if name.startswith("src/")}
    if not src:
        sys.exit(f"coverage: no src/ records in {path} (did the spec run?)")

    total_cov = total = 0
    print(f"{'file':28} {'cov%':>6}  covered/total", file=sys.stderr)
    for name in sorted(src):
        cov = sum(1 for hit in src[name].values() if hit)
        tot = len(src[name])
        total_cov += cov
        total += tot
        print(f"{name[4:]:28} {100 * cov / tot:5.1f}%  {cov}/{tot}", file=sys.stderr)
    pct = 100 * total_cov / total
    print("-" * 50, file=sys.stderr)
    print(f"{'TOTAL':28} {pct:5.1f}%  {total_cov}/{total}", file=sys.stderr)

    print(f"{pct:.1f}")


if __name__ == "__main__":
    main()
