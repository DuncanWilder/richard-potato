#!/usr/bin/env python3
"""Require a filled Verification section in the PR body."""
import json
import re
import sys

body = json.load(open(sys.argv[1]))['pull_request'].get('body') or ''
section = re.search(r'^## Verification\s*\n(.*?)(?=^## |\Z)', body, re.M | re.S)
content = re.sub(r'<!--.*?-->', '', section[1], flags=re.S).strip() if section else ''
if not content or not re.search(r'[A-Za-z0-9]', content):
    sys.exit('Fill in the required ## Verification section with commands and results.')
