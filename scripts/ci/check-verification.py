#!/usr/bin/env python3
"""Require a filled Verification section in the PR body."""
import json
import re
import sys

body = json.load(open(sys.argv[1]))['pull_request'].get('body') or ''
required = ['What and why', 'Root cause', 'Verification', 'Screenshots']
visible = re.sub(r'<!--.*?-->', '', body, flags=re.S)
headings = re.findall(r'^## ([^\r\n]+)\r?$', visible, re.M)
if headings != required:
    sys.exit('PR body must use these headings in order: ' + ', '.join(required))
for heading in required:
    match = re.search(r'^## ' + re.escape(heading) + r'\s*\n(.*?)(?=^## |\Z)', visible, re.M | re.S)
    if not match or not re.search(r'[A-Za-z0-9]', match[1]):
        sys.exit(f'Fill in the required ## {heading} section; use N/A where applicable.')
section = re.search(r'^## Verification\s*\n(.*?)(?=^## |\Z)', body, re.M | re.S)
content = re.sub(r'<!--.*?-->', '', section[1], flags=re.S).strip() if section else ''
if not content or not re.search(r'[A-Za-z0-9]', content):
    sys.exit('Fill in the required ## Verification section with commands and results.')
