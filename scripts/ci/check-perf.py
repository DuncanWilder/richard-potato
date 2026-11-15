#!/usr/bin/env python3
"""Require a Markdown before/after measurement table for perf PRs."""
import json
import re
import sys

pr = json.load(open(sys.argv[1]))['pull_request']
if not re.match(r'^perf(?:\([^)]*\))?!?:', pr['title']):
    sys.exit(0)
lines = (pr.get('body') or '').splitlines()
for i, line in enumerate(lines[:-2]):
    cells = [c.strip().lower() for c in line.strip().strip('|').split('|')]
    if 'before' in cells and 'after' in cells:
        separator = lines[i + 1].strip().strip('|').split('|')
        if len(separator) != len(cells) or not all(re.fullmatch(r'\s*:?-{3,}:?\s*', c) for c in separator):
            continue
        for row in lines[i + 2:]:
            values = [c.strip() for c in row.strip().strip('|').split('|')]
            if len(values) != len(cells):
                break
            if all(re.search(r'\d', values[cells.index(c)]) for c in ('before', 'after')):
                sys.exit(0)
sys.exit('perf PRs require a table with Before and After columns and numeric measurements.')
