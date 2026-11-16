#!/usr/bin/env python3
"""Validate the PR title from a GitHub event JSON file."""
import json
import re
import sys

pr = json.load(open(sys.argv[1]))['pull_request']
if not re.fullmatch(r'(feat|fix|perf|chore|docs|refactor|test|ci|build)(\([\w./-]+\))?!?: \S[^\r\n]*', pr['title']):
    sys.exit('PR title must be a Conventional Commit: type(scope)!: description')
